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

    /// In-flight removal tasks keyed by session id. A late event can cancel
    /// the pending removal and re-activate the session, instead of having
    /// the timer fire and silently delete a freshly-recreated session with
    /// the same id (issues #8, #9, #10).
    private var pendingRemovals: [String: Task<Void, Never>] = [:]

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

            // Strategy 1: PID probe — also check process start time so we
            // don't keep a dead session alive forever because the kernel
            // recycled the pid to some unrelated process (issue #29).
            if let pid = session.agentPid {
                let result = kill(pid_t(pid), 0)
                if result != 0 && errno == ESRCH {
                    shouldClose = true
                } else if let startSec = session.agentStartSec,
                          let startUsec = session.agentStartUsec,
                          let now = Self.processStartTime(pid: pid_t(pid)),
                          (Int(now.tv_sec) != startSec || Int(now.tv_usec) != startUsec) {
                    // PID is alive but it's a different process now.
                    shouldClose = true
                }
            }

            // Strategy 2: inactivity timeout (Codex only — PID is unreliable
            // because hooks route through a long-lived daemon). Skip when
            // a tool is in flight — Codex emits PreToolUse then nothing
            // until PostToolUse, and we'd kill the session mid-tool on
            // anything that takes more than 5 minutes (issue #11).
            if !shouldClose && session.source == "codex" && session.status == .idle {
                if now.timeIntervalSince(session.lastActivityAt) > codexIdleThreshold {
                    shouldClose = true
                }
            }

            if shouldClose {
                markCompletedAndScheduleRemoval(sessionId: id, after: 2.0)
            }
        }
    }

    // MARK: - Removal helpers

    /// Mark the session completed, emit `sessionEnded`, and schedule its
    /// removal after `delay`. A late hook arrival within `delay` cancels
    /// the removal and resurrects the session via `handleLateEvent`.
    private func markCompletedAndScheduleRemoval(sessionId: String, after delay: TimeInterval) {
        guard sessions[sessionId]?.status != .completed else { return }
        sessions[sessionId]?.status = .completed
        onEvent.send(.sessionEnded(sessionId))
        scheduleRemoval(sessionId: sessionId, after: delay)
    }

    private func scheduleRemoval(sessionId: String, after delay: TimeInterval) {
        pendingRemovals[sessionId]?.cancel()
        pendingRemovals[sessionId] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            await MainActor.run {
                guard let self else { return }
                self.pendingRemovals.removeValue(forKey: sessionId)
                // Re-check completed — a brand-new session with the same id
                // (Claude --resume, Codex thread reuse) will have status
                // reset to .idle / .thinking by ensureSession + handleMessage.
                if self.sessions[sessionId]?.status == .completed {
                    self.sessions.removeValue(forKey: sessionId)
                }
            }
        }
    }

    private func cancelPendingRemoval(sessionId: String) {
        pendingRemovals[sessionId]?.cancel()
        pendingRemovals.removeValue(forKey: sessionId)
    }

    /// Returns the start time of the process at `pid`, or nil if it's
    /// unreadable. Used to detect PID reuse alongside `kill(pid, 0)`.
    private static func processStartTime(pid: pid_t) -> timeval? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let result = withUnsafeMutablePointer(to: &mib[0]) { mibPtr in
            sysctl(mibPtr, 4, &info, &size, nil, 0)
        }
        if result == 0 {
            return info.kp_proc.p_starttime
        }
        return nil
    }

    var activeSessions: [String: Session] {
        sessions.filter { $0.value.status != .completed }
    }

    private func ensureSession(_ message: BridgeMessage) {
        let sessionId = message.sessionId
        if sessions[sessionId] == nil {
            let cwd = message.cwd ?? "~"
            var s = Session(
                id: sessionId,
                cwd: cwd,
                startedAt: Date(),
                status: .idle,
                terminalInfo: message.terminalInfo,
                source: message.source ?? "claude"
            )
            s.cwdIsPlaceholder = (message.cwd == nil)
            s.announced = true
            sessions[sessionId] = s
            onEvent.send(.sessionStarted(sessionId))
        } else if let cwd = message.cwd, !cwd.isEmpty,
                  sessions[sessionId]?.cwdIsPlaceholder == true {
            // First real cwd arrives after a placeholder create (issue #38).
            sessions[sessionId]?.cwd = cwd
            sessions[sessionId]?.cwdIsPlaceholder = false
        }
        // Update terminal info / source if newer info arrives
        if let info = message.terminalInfo {
            sessions[sessionId]?.terminalInfo = info
        }
        if let src = message.source {
            sessions[sessionId]?.source = src
        }
    }

    /// The canonical events the store understands. Every provider bridge
    /// normalizes its native vocabulary to one of these before sending; a
    /// message arriving with a raw, un-normalized name (e.g. Cursor's
    /// "beforeSubmitPrompt"/"stop") bypassed our normalization and belongs to
    /// a foreign/misconfigured integration sharing the socket — drop it so it
    /// can't create phantom sessions or clobber a correctly-attributed one.
    private static let canonicalEvents: Set<String> = [
        "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
        "PermissionRequest", "Stop", "Notification", "SubagentStart", "SubagentStop", "PreCompact",
    ]

    func handleMessage(_ message: BridgeMessage, respond: ((BridgeResponse) -> Void)?, respondRaw: ((Data) -> Void)? = nil) {
        let sessionId = message.sessionId
        guard Self.canonicalEvents.contains(message.hookEvent) else {
            Log.info("Ignoring non-canonical event '\(message.hookEvent)' from source=\(message.source ?? "?") session=\(sessionId.prefix(8))")
            return
        }
        ensureSession(message)
        // A late buffered hook may arrive after we've marked a session
        // .completed and scheduled removal. Cancel the pending removal so
        // the brand-new session (Claude resume / Codex thread reuse) isn't
        // deleted out from under us, and reset .completed back to .idle so
        // the per-event switch below can transition normally (issue #10).
        if sessions[sessionId]?.status == .completed {
            cancelPendingRemoval(sessionId: sessionId)
            sessions[sessionId]?.status = .idle
        }
        // Stamp activity time on every event so the collapsed notch tracks
        // whatever provider is most recently doing something.
        sessions[sessionId]?.lastActivityAt = Date()
        let statusBefore = sessions[sessionId]?.status

        // Always update effort level if present (it's on most hooks)
        if let effort = message.effortLevel {
            sessions[sessionId]?.effortLevel = effort
        }
        // Stamp the model whenever the hook carries one.
        if let m = message.model, !m.isEmpty {
            sessions[sessionId]?.model = m
        }
        // Always update session title if present
        if let title = message.sessionTitle, !title.isEmpty {
            sessions[sessionId]?.sessionTitle = title
        }
        // Capture the agent PID — used to detect when the agent exits.
        // Also stamp its start time so PID reuse can be detected later
        // (issue #29).
        if let pid = message.agentPid, pid > 0 {
            if sessions[sessionId]?.agentPid != pid {
                sessions[sessionId]?.agentPid = pid
                if let start = Self.processStartTime(pid: pid_t(pid)) {
                    sessions[sessionId]?.agentStartSec = Int(start.tv_sec)
                    sessions[sessionId]?.agentStartUsec = Int(start.tv_usec)
                }
            }
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
            // ensureSession already emitted .sessionStarted for first-time
            // creates. Suppress the redundant SessionStart-hook emit so
            // subscribers (sounds, metrics) see exactly one start per id
            // (issue #37).
            if sessions[sessionId]?.announced == false {
                sessions[sessionId]?.announced = true
                onEvent.send(.sessionStarted(sessionId))
            }

        case "SessionEnd":
            markCompletedAndScheduleRemoval(sessionId: sessionId, after: 5.0)

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
                                // For Codex, persist a prefix_rule for Bash only;
                                // non-Bash tools can't be matched against
                                // shell-command prefixes (issue #17). Either way,
                                // ack the current call with a one-shot allow.
                                let persisted = CodexPermissionRules.persistAlwaysAllow(toolName: toolName, toolInput: description)
                                if !persisted {
                                    Log.info("Codex Allow All not persisted for tool=\(toolName); allowing once")
                                }
                                respond?(BridgeResponse.allow())
                            } else if let data = BridgeResponse.allowAllForTool(toolName), respondRaw != nil {
                                Log.info("Sending Claude allowAll raw data (\(data.count) bytes)")
                                respondRaw?(data)
                            } else {
                                respond?(BridgeResponse.allow())
                            }
                        case .bypass:
                            if isCodex {
                                let persisted = CodexPermissionRules.persistAlwaysAllow(toolName: toolName, toolInput: description, broad: true)
                                if !persisted {
                                    Log.info("Codex Bypass not persisted for tool=\(toolName); allowing once")
                                }
                                respond?(BridgeResponse.allow())
                            } else if let data = BridgeResponse.bypass(), respondRaw != nil {
                                Log.info("Sending Claude bypass raw data (\(data.count) bytes)")
                                respondRaw?(data)
                            } else {
                                respond?(BridgeResponse.allow())
                            }
                        case .deferToApp:
                            // behavior "ask" → the bridge translates this to the
                            // tool's native defer (Cursor "ask" / Copilot "ask"),
                            // so the agent shows its own prompt; we also jump to it.
                            if let data = BridgeResponse.deferToTerminal(), respondRaw != nil {
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
        let session = sessions[sessionId]
        // Clear immediately so nextPendingPermission() won't find it again
        sessions[sessionId]?.pendingPermission = nil
        sessions[sessionId]?.status = .thinking
        pending.respond(action)
        onEvent.send(.permissionResponded(sessionId, action != .deny))
        // Defer-to-app: surface the tool so the user can answer its own prompt.
        if action == .deferToApp, let session {
            TerminalJumper.jump(to: session)
        }
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
                let cwd = info.cwd ?? "~"
                var s = Session(
                    id: id,
                    cwd: cwd,
                    startedAt: Date(),
                    status: .idle,
                    source: "codex"
                )
                s.cwdIsPlaceholder = (info.cwd == nil)
                s.announced = true
                if let name = info.name, !name.isEmpty {
                    s.sessionTitle = name
                }
                sessions[id] = s
                onEvent.send(.sessionStarted(id))
            } else {
                // Update title for existing sessions if we got a name.
                if let name = info.name, !name.isEmpty {
                    let current = sessions[id]?.sessionTitle ?? ""
                    if current.isEmpty || current == sessions[id]?.projectName {
                        sessions[id]?.sessionTitle = name
                    }
                }
                // Apply a real cwd if we still have only the placeholder
                // (issue #38).
                if let cwd = info.cwd, !cwd.isEmpty,
                   sessions[id]?.cwdIsPlaceholder == true {
                    sessions[id]?.cwd = cwd
                    sessions[id]?.cwdIsPlaceholder = false
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

    /// Called from QuestionView with answers keyed by `QuestionItem.id`.
    /// Multi-select answers come as comma-joined option labels — matches
    /// Claude Code's documented format.
    func respondToQuestion(sessionId: String, answersByQuestionId: [String: String]) {
        guard let q = sessions[sessionId]?.pendingQuestion else { return }

        // BridgeResponse.allowWithAnswers expects answers keyed by the
        // question text (Claude's convention), so translate.
        var answersByText: [String: String] = [:]
        for question in q.questions {
            if let v = answersByQuestionId[question.id] {
                answersByText[question.question] = v
            }
        }

        Log.info("Question answers: \(answersByText)")

        // Clear immediately so nextPendingQuestion() won't find it again
        sessions[sessionId]?.pendingQuestion = nil
        sessions[sessionId]?.status = .thinking

        if let data = BridgeResponse.allowWithAnswers(questions: q.questions, answers: answersByText) {
            q.respond(data)
        }
    }
}
