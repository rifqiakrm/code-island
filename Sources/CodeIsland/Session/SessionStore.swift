import Foundation
import Combine

enum SessionEvent {
    case sessionStarted(String)
    case sessionEnded(String)
    case statusChanged(String, SessionStatus)
    case toolStarted(String, String)
    case toolEnded(String, String)
    case permissionRequested(String)
    case permissionResponded(String, Bool)
    case questionAsked(String)
    case pendingDismissedExternally(String)
    case notification(String, String)
}

@MainActor
final class SessionStore: ObservableObject {
    @Published var sessions: [String: Session] = [:]

    let onEvent = PassthroughSubject<SessionEvent, Never>()

    /// Polls every 5s to check whether the AI agent process is still alive.
    /// Cleaner than time-based cleanup because long idle sessions stay open
    /// while genuinely-exited sessions get removed quickly.
    private var processSweepTimer: Timer?

    init() {
        processSweepTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sweepClosedAgents() }
        }
    }

    deinit {
        processSweepTimer?.invalidate()
    }

    /// Marks sessions whose agent has exited as ended, then removes them.
    ///
    /// Two detection strategies, used in parallel:
    ///   1. PID probe via `kill(pid, 0)` — reliable for Claude, where the
    ///      hook bridge's `getppid()` returns the agent's own short-lived
    ///      process. Returns -1 with errno=ESRCH when the process is gone.
    ///   2. Codex-only inactivity timeout — Codex routes hooks through a
    ///      persistent `app-server` daemon (the bridge's parent is always
    ///      that long-lived process), so PID detection never fires. If a
    ///      Codex session goes 5+ minutes without ANY hook, we treat it as
    ///      ended. 5 minutes is conservative enough that an actively-used
    ///      session won't be killed even mid-tool-call.
    private func sweepClosedAgents() {
        let codexIdleThreshold: TimeInterval = 5 * 60
        let now = Date()

        for (id, session) in sessions {
            guard session.status != .completed else { continue }

            var shouldClose = false

            // Strategy 1: PID probe (works for Claude)
            if let pid = session.agentPid {
                let result = kill(pid_t(pid), 0)
                if result != 0 && errno == ESRCH {
                    shouldClose = true
                }
            }

            // Strategy 2: inactivity timeout (Codex only — PID is unreliable)
            if !shouldClose && session.source == "codex" {
                if now.timeIntervalSince(session.lastActivityAt) > codexIdleThreshold {
                    shouldClose = true
                }
            }

            if shouldClose {
                sessions[id]?.status = .completed
                onEvent.send(.sessionEnded(id))
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    await MainActor.run { self?.sessions.removeValue(forKey: id) }
                }
            }
        }
    }

    var activeSessions: [String: Session] {
        sessions.filter { $0.value.status != .completed }
    }

    private func ensureSession(_ message: BridgeMessage) {
        let sessionId = message.sessionId
        if sessions[sessionId] == nil {
            sessions[sessionId] = Session(
                id: sessionId,
                cwd: message.cwd ?? "~",
                startedAt: Date(),
                status: .idle,
                terminalInfo: message.terminalInfo,
                source: message.source ?? "claude"
            )
        }
        // Update terminal info / source if newer info arrives
        if let info = message.terminalInfo {
            sessions[sessionId]?.terminalInfo = info
        }
        if let src = message.source {
            sessions[sessionId]?.source = src
        }
    }

    func handleMessage(_ message: BridgeMessage, respond: ((BridgeResponse) -> Void)?, respondRaw: ((Data) -> Void)? = nil) {
        let sessionId = message.sessionId
        ensureSession(message)
        // Stamp activity time on every event so the collapsed notch tracks
        // whatever provider is most recently doing something.
        sessions[sessionId]?.lastActivityAt = Date()
        let statusBefore = sessions[sessionId]?.status

        // Always update effort level if present (it's on most hooks)
        if let effort = message.effortLevel {
            sessions[sessionId]?.effortLevel = effort
        }
        // Always update session title if present
        if let title = message.sessionTitle, !title.isEmpty {
            sessions[sessionId]?.sessionTitle = title
        }
        // Capture the agent PID — used to detect when the agent exits
        if let pid = message.agentPid, pid > 0 {
            sessions[sessionId]?.agentPid = pid
        }

        // If a new event arrives while a permission/question is still pending,
        // the user must have answered it via the terminal — dismiss the notch.
        // Critical: capture the respond closures BEFORE clearing pending state
        // and invoke them with safe defaults so the socket fd closes and the
        // bridge unblocks. Dropping the closures without invoking them leaks
        // the fd and leaves the bridge in read() for 300s (issue #2).
        let isProgressEvent = ["PreToolUse", "PostToolUse", "UserPromptSubmit", "Stop"].contains(message.hookEvent)
        if isProgressEvent {
            let droppedPermission = sessions[sessionId]?.pendingPermission
            let droppedQuestion = sessions[sessionId]?.pendingQuestion
            if droppedPermission != nil || droppedQuestion != nil {
                sessions[sessionId]?.pendingPermission = nil
                sessions[sessionId]?.pendingQuestion = nil
                // Allow-once for orphaned permissions — the user already
                // answered in the terminal, so we're just acking the protocol.
                droppedPermission?.respond(.allowOnce)
                // For orphaned questions, defer-to-terminal so Claude knows
                // to fall through to its native prompt. (No-op for Codex
                // where respond is just a TerminalJumper hook.)
                if let q = droppedQuestion, let data = BridgeResponse.deferToTerminal() {
                    q.respond(data)
                }
                Log.info("Pending resolved externally for session=\(sessionId.prefix(8)) (event=\(message.hookEvent))")
                onEvent.send(.pendingDismissedExternally(sessionId))
            }
        }

        switch message.hookEvent {
        case "SessionStart":
            sessions[sessionId]?.status = .idle
            onEvent.send(.sessionStarted(sessionId))

        case "SessionEnd":
            sessions[sessionId]?.status = .completed
            onEvent.send(.sessionEnded(sessionId))
            Task {
                try? await Task.sleep(for: .seconds(5))
                sessions.removeValue(forKey: sessionId)
            }

        case "UserPromptSubmit":
            let userMsg = message.userMessage ?? message.toolInput
            if let msg = userMsg {
                sessions[sessionId]?.lastUserMessage = msg
                if sessions[sessionId]?.firstPrompt == nil {
                    sessions[sessionId]?.firstPrompt = msg
                }
            }
            sessions[sessionId]?.status = .thinking
            sessions[sessionId]?.currentTool = nil
            onEvent.send(.statusChanged(sessionId, .thinking))

        case "PreToolUse":
            let toolName = message.toolName ?? "unknown"
            sessions[sessionId]?.status = .toolUse
            sessions[sessionId]?.currentTool = toolName
            onEvent.send(.toolStarted(sessionId, toolName))

            // Codex's AskUserQuestion equivalent — fires through PreToolUse, not
            // PermissionRequest. We can't reply via the hook (Codex PreToolUse
            // only supports allow/deny, not substituting an answer), so we
            // mirror the question in the notch and route any click to the app.
            if (message.source ?? "claude") == "codex",
               toolName == "request_user_input",
               let desc = message.toolInput,
               let parsedQuestions = Self.parseQuestion(desc) {
                sessions[sessionId]?.status = .waitingPermission
                sessions[sessionId]?.pendingQuestion = PendingQuestion(
                    questions: parsedQuestions,
                    respond: { [weak self] _ in
                        // Can't answer via hook — surface Codex.app so the
                        // user finishes there. PostToolUse will dismiss the
                        // notch's question view once they've answered.
                        if let session = self?.sessions[sessionId] {
                            TerminalJumper.jump(to: session)
                        }
                    }
                )
                onEvent.send(.questionAsked(sessionId))
            }

        case "PostToolUse":
            let toolName = message.toolName ?? "unknown"
            sessions[sessionId]?.status = .thinking
            sessions[sessionId]?.currentTool = nil
            sessions[sessionId]?.lastToolDurationMs = message.durationMs
            // Don't update lastAssistantMessage from tool output
            onEvent.send(.toolEnded(sessionId, toolName))

        case "PermissionRequest":
            let toolName = message.toolName ?? "unknown"
            let description = message.toolInput

            // Auto-allow if bypass permissions mode — but NOT for
            // AskUserQuestion. Claude requires updatedInput.answers in the
            // response; a bare allow() makes the assistant proceed with no
            // user input. Fall through so the question UI runs (issue #5).
            if message.permissionMode == "bypassPermissions",
               toolName != "AskUserQuestion" {
                Log.info("Bypass mode — auto-allowing \(toolName) for session=\(sessionId.prefix(8))")
                let response = BridgeResponse.allow()
                respond?(response)
                return
            }

            // Detect AskUserQuestion — show question UI instead of permission UI
            if toolName == "AskUserQuestion", let desc = description,
               let parsedQuestions = Self.parseQuestion(desc) {
                sessions[sessionId]?.status = .waitingPermission
                sessions[sessionId]?.pendingQuestion = PendingQuestion(
                    questions: parsedQuestions,
                    respond: { rawData in
                        Log.info("Question answered for session=\(sessionId.prefix(8))")
                        // State is already cleared by respondToQuestion() synchronously
                        respondRaw?(rawData)
                    }
                )
                onEvent.send(.questionAsked(sessionId))
            } else {
                sessions[sessionId]?.status = .waitingPermission
                sessions[sessionId]?.pendingPermission = PendingPermission(
                    toolName: toolName,
                    description: description,
                    filePath: message.toolFilePath,
                    content: message.toolContent,
                    oldString: message.toolOldString,
                    newString: message.toolNewString,
                    respond: { [weak self] action in
                        Log.info("Permission responded: \(action) for session=\(sessionId.prefix(8)), respondRaw=\(respondRaw != nil)")
                        // State is already cleared by respondToPermission() synchronously.
                        // Codex rejects Claude's `updatedPermissions` shape, so we
                        // persist allow-all / bypass via a TOML rules file instead
                        // and return a plain `behavior: allow`.
                        let isCodex = self?.sessions[sessionId]?.source == "codex"
                        switch action {
                        case .deny:
                            respond?(BridgeResponse.deny())
                        case .allowOnce:
                            respond?(BridgeResponse.allow())
                        case .allowAll:
                            if isCodex {
                                CodexPermissionRules.persistAlwaysAllow(toolName: toolName, toolInput: description)
                                respond?(BridgeResponse.allow())
                            } else if let data = BridgeResponse.allowAllForTool(toolName), respondRaw != nil {
                                Log.info("Sending Claude allowAll raw data (\(data.count) bytes)")
                                respondRaw?(data)
                            } else {
                                respond?(BridgeResponse.allow())
                            }
                        case .bypass:
                            if isCodex {
                                CodexPermissionRules.persistAlwaysAllow(toolName: toolName, toolInput: description, broad: true)
                                respond?(BridgeResponse.allow())
                            } else if let data = BridgeResponse.bypass(), respondRaw != nil {
                                Log.info("Sending Claude bypass raw data (\(data.count) bytes)")
                                respondRaw?(data)
                            } else {
                                respond?(BridgeResponse.allow())
                            }
                        }
                    }
                )
                onEvent.send(.permissionRequested(sessionId))
            }

        case "Stop":
            if let msg = message.assistantMessage {
                sessions[sessionId]?.lastAssistantMessage = msg
            }
            sessions[sessionId]?.status = .idle
            sessions[sessionId]?.currentTool = nil
            onEvent.send(.statusChanged(sessionId, .idle))

        case "Notification":
            if let msg = message.assistantMessage {
                sessions[sessionId]?.lastAssistantMessage = msg
            }
            let text = message.notification ?? ""
            onEvent.send(.notification(sessionId, text))

        case "SubagentStart":
            sessions[sessionId]?.currentTool = "Agent"
            onEvent.send(.toolStarted(sessionId, "Agent"))

        case "SubagentStop":
            sessions[sessionId]?.currentTool = nil
            onEvent.send(.toolEnded(sessionId, "Agent"))

        case "PreCompact":
            break

        default:
            break
        }

        // Maintain the live "active timer" used by the session card. Starts when
        // we first enter an active state from idle; carries through across
        // thinking ↔ toolUse transitions; resets when we go back to idle.
        if let after = sessions[sessionId]?.status {
            let wasActive = statusBefore == .thinking || statusBefore == .toolUse
            let isActive = after == .thinking || after == .toolUse
            if isActive && !wasActive {
                sessions[sessionId]?.activeStartedAt = Date()
            } else if !isActive {
                sessions[sessionId]?.activeStartedAt = nil
            }
        }
    }

    // MARK: - Question Parsing

    private static func parseQuestion(_ json: String) -> [QuestionItem]? {
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let questions = parsed["questions"] as? [[String: Any]],
              !questions.isEmpty else {
            return nil
        }

        return questions.enumerated().map { qIndex, q in
            let questionText = q["question"] as? String ?? ""
            let header = q["header"] as? String
            let multiSelect = q["multiSelect"] as? Bool ?? false
            let options = (q["options"] as? [[String: Any]] ?? []).enumerated().map { oIndex, opt in
                QuestionOption(
                    id: opt["label"] as? String ?? "q\(qIndex)_o\(oIndex)",
                    label: opt["label"] as? String ?? "Option \(oIndex + 1)",
                    description: opt["description"] as? String
                )
            }
            return QuestionItem(
                id: "q\(qIndex)",
                header: header,
                question: questionText,
                options: options,
                multiSelect: multiSelect
            )
        }
    }

    func respondToPermission(sessionId: String, action: PermissionAction) {
        guard let pending = sessions[sessionId]?.pendingPermission else { return }
        // Clear immediately so nextPendingPermission() won't find it again
        sessions[sessionId]?.pendingPermission = nil
        sessions[sessionId]?.status = .thinking
        pending.respond(action)
        onEvent.send(.permissionResponded(sessionId, action != .deny))
    }

    /// Apply renamed Codex session titles fetched from the codex app-server.
    /// Matches by `session_id` since Codex's hook session id is the same UUID
    /// it reports as `thread.id` from the JSON-RPC stream. Sessions that
    /// already have a title (user-provided or from Claude) are left alone.
    func applyCodexThreadNames(_ names: [String: String]) {
        for (threadId, name) in names {
            guard var session = sessions[threadId] else { continue }
            // Only overwrite the title if the existing one is empty or matches
            // the auto-derived fallback (folder name / first prompt).
            let current = session.sessionTitle ?? ""
            if current.isEmpty || current == session.projectName {
                session.sessionTitle = name
                sessions[threadId] = session
            }
        }
    }

    /// Called when the Codex app-server reports a thread/closed event.
    /// The bridge can't detect this on its own — Codex CLI/GUI both route
    /// hooks through the long-lived daemon, so `agent_pid` always points at
    /// a process that never dies. The daemon's JSON-RPC stream is the only
    /// reliable signal that a Codex session has actually ended.
    func handleCodexThreadClosed(_ threadId: String) {
        guard let session = sessions[threadId] else { return }
        guard session.source == "codex" else { return }
        guard session.status != .completed else { return }
        sessions[threadId]?.status = .completed
        onEvent.send(.sessionEnded(threadId))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { self?.sessions.removeValue(forKey: threadId) }
        }
    }

    /// Mirror the app-server thread stream into proper Session records.
    ///
    /// Codex doesn't fire a SessionStart hook on `codex resume <id>` — hooks
    /// only kick in once the user submits a prompt. The app-server stream,
    /// however, emits a `thread/started` notification immediately on resume.
    /// We use that to surface the session in the notch right away instead of
    /// waiting for the first prompt.
    ///
    /// Sessions created this way are intentionally bare: cwd if we got it,
    /// the renamed title if any, status=.idle. Real hook payloads later
    /// enrich them with terminal info, PIDs, prompts, etc.
    func applyCodexThreads(_ infos: [String: CodexThreadInfo]) {
        // Create sessions for newly-discovered threads.
        for (id, info) in infos {
            if sessions[id] == nil {
                sessions[id] = Session(
                    id: id,
                    cwd: info.cwd ?? "~",
                    startedAt: Date(),
                    status: .idle,
                    source: "codex"
                )
                if let name = info.name, !name.isEmpty {
                    sessions[id]?.sessionTitle = name
                }
                onEvent.send(.sessionStarted(id))
            } else {
                // Update title for existing sessions if we got a name.
                if let name = info.name, !name.isEmpty {
                    let current = sessions[id]?.sessionTitle ?? ""
                    if current.isEmpty || current == sessions[id]?.projectName {
                        sessions[id]?.sessionTitle = name
                    }
                }
                if let cwd = info.cwd, !cwd.isEmpty, sessions[id]?.cwd == "~" {
                    sessions[id]?.cwd = cwd
                }
            }
        }
    }

    /// Returns the session ID of the next session with a pending permission,
    /// ordered by enqueue time (oldest first) for deterministic FIFO across
    /// arbitrary dictionary iteration (issue #6).
    func nextPendingPermission() -> String? {
        sessions.values
            .compactMap { s -> (id: String, at: Date)? in
                guard let p = s.pendingPermission else { return nil }
                return (s.id, p.requestedAt)
            }
            .min(by: { $0.at < $1.at })?.id
    }

    /// Returns the session ID of the next session with a pending question,
    /// ordered by enqueue time (oldest first).
    func nextPendingQuestion() -> String? {
        sessions.values
            .compactMap { s -> (id: String, at: Date)? in
                guard let q = s.pendingQuestion else { return nil }
                return (s.id, q.requestedAt)
            }
            .min(by: { $0.at < $1.at })?.id
    }

    /// Defer the pending question to the terminal (Claude Code will prompt there).
    func deferQuestionToTerminal(sessionId: String) {
        guard let q = sessions[sessionId]?.pendingQuestion else { return }
        sessions[sessionId]?.pendingQuestion = nil
        sessions[sessionId]?.status = .thinking
        if let data = BridgeResponse.deferToTerminal() {
            q.respond(data)
        }
        // Jump to the terminal so the user can answer there
        if let session = sessions[sessionId] {
            TerminalJumper.jump(to: session)
        }
    }

    /// Called from QuestionView with answers formatted as "answer1|answer2|..."
    func respondToQuestion(sessionId: String, answer: String) {
        guard let q = sessions[sessionId]?.pendingQuestion else { return }

        // Parse "answer1|answer2" into a dict mapping question text → selected labels
        let parts = answer.components(separatedBy: "|")
        var answersDict: [String: String] = [:]
        for (index, question) in q.questions.enumerated() {
            if index < parts.count {
                answersDict[question.question] = parts[index]
            }
        }

        Log.info("Question answers: \(answersDict)")

        // Clear immediately so nextPendingQuestion() won't find it again
        sessions[sessionId]?.pendingQuestion = nil
        sessions[sessionId]?.status = .thinking

        if let data = BridgeResponse.allowWithAnswers(questions: q.questions, answers: answersDict) {
            q.respond(data)
        }
    }
}
