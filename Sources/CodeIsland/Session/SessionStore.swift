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
    case notification(String, String)
}

@MainActor
final class SessionStore: ObservableObject {
    @Published var sessions: [String: Session] = [:]

    let onEvent = PassthroughSubject<SessionEvent, Never>()

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
                terminalInfo: message.terminalInfo
            )
        }
        // Update terminal info if available
        if let info = message.terminalInfo {
            sessions[sessionId]?.terminalInfo = info
        }
    }

    func handleMessage(_ message: BridgeMessage, respond: ((BridgeResponse) -> Void)?, respondRaw: ((Data) -> Void)? = nil) {
        let sessionId = message.sessionId
        ensureSession(message)

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

        case "PostToolUse":
            let toolName = message.toolName ?? "unknown"
            sessions[sessionId]?.status = .thinking
            sessions[sessionId]?.currentTool = nil
            // Don't update lastAssistantMessage from tool output
            onEvent.send(.toolEnded(sessionId, toolName))

        case "PermissionRequest":
            let toolName = message.toolName ?? "unknown"
            let description = message.toolInput

            // Auto-allow if bypass permissions mode
            if message.permissionMode == "bypassPermissions" {
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
                    respond: { action in
                        Log.info("Permission responded: \(action) for session=\(sessionId.prefix(8)), respondRaw=\(respondRaw != nil)")
                        // State is already cleared by respondToPermission() synchronously
                        switch action {
                        case .deny:
                            respond?(BridgeResponse.deny())
                        case .allowOnce:
                            respond?(BridgeResponse.allow())
                        case .allowAll:
                            if let data = BridgeResponse.allowAllForTool(toolName), respondRaw != nil {
                                Log.info("Sending allowAll raw data (\(data.count) bytes)")
                                respondRaw?(data)
                            } else {
                                Log.info("Falling back to simple allow for allowAll")
                                respond?(BridgeResponse.allow())
                            }
                        case .bypass:
                            if let data = BridgeResponse.bypass(), respondRaw != nil {
                                Log.info("Sending bypass raw data (\(data.count) bytes)")
                                respondRaw?(data)
                            } else {
                                Log.info("Falling back to simple allow for bypass")
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

    /// Returns the session ID of the next session with a pending permission, if any.
    func nextPendingPermission() -> String? {
        sessions.first(where: { $0.value.pendingPermission != nil })?.key
    }

    /// Returns the session ID of the next session with a pending question, if any.
    func nextPendingQuestion() -> String? {
        sessions.first(where: { $0.value.pendingQuestion != nil })?.key
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
