import Foundation

enum SessionStatus: String, Codable, Equatable {
    case idle
    case thinking
    case toolUse
    case waitingPermission
    case error
    case completed

    var displayText: String {
        switch self {
        case .idle: return "Idle"
        case .thinking: return "Thinking..."
        case .toolUse: return "Using tool"
        case .waitingPermission: return "Needs approval"
        case .error: return "Error"
        case .completed: return "Done"
        }
    }
}

enum PermissionAction {
    case deny
    case allowOnce
    case allowAll
    case bypass
}

struct PendingPermission {
    let toolName: String
    let description: String?
    let filePath: String?
    let content: String?
    let oldString: String?
    let newString: String?
    let respond: (PermissionAction) -> Void
}

struct PendingQuestion {
    let questions: [QuestionItem]
    /// Respond with raw JSON data to write to the socket
    let respond: (Data) -> Void
}

struct QuestionItem: Identifiable {
    let id: String
    let header: String?
    let question: String
    let options: [QuestionOption]
    let multiSelect: Bool
}

struct QuestionOption: Identifiable {
    let id: String
    let label: String
    let description: String?
}

struct Session: Identifiable {
    let id: String
    let cwd: String
    let startedAt: Date
    var status: SessionStatus
    var currentTool: String?
    var pendingPermission: PendingPermission?
    var pendingQuestion: PendingQuestion?
    var terminalInfo: TerminalInfo?
    var firstPrompt: String?
    var lastUserMessage: String?
    var lastAssistantMessage: String?
    var terminalApp: String?
    var effortLevel: String?
    var lastToolDurationMs: Int?
    var sessionTitle: String?

    var projectName: String {
        (cwd as NSString).lastPathComponent
    }

    /// Preferred display name — uses Claude's session title if set, else falls back to folder name.
    var displayName: String {
        if let title = sessionTitle, !title.isEmpty { return title }
        return projectName
    }

    var durationText: String {
        let elapsed = Date().timeIntervalSince(startedAt)
        let minutes = Int(elapsed) / 60
        if minutes >= 60 {
            return "\(minutes / 60)h"
        }
        if minutes > 0 {
            return "<\(minutes + 1)m"
        }
        return "<1m"
    }

    var detectedTerminalApp: String {
        if let app = terminalApp { return app }
        return TerminalJumper.appName(for: terminalInfo?.appBundleId)
    }
}

struct TerminalInfo {
    var itermSessionId: String?
    var termSessionId: String?
    var tmuxPane: String?
    var tty: String?
    var appBundleId: String?
    var kittyWindowId: String?
    var weztermSocket: String?
}
