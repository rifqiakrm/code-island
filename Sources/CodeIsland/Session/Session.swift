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
    var cwd: String
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
    /// AI provider identifier (claude / codex / gemini / ...).
    /// Defaults to "claude" if the bridge doesn't stamp a source.
    var source: String = "claude"
    /// Time of the most recent event from this session — used so the collapsed
    /// notch tracks the *currently active* session, not just whichever was opened first.
    var lastActivityAt: Date = .init()
    /// When the session most recently entered an active state (thinking/toolUse).
    /// Cleared when status returns to idle. Used to render the live "Xms" counter.
    var activeStartedAt: Date?
    /// PID of the AI agent process (Claude / Codex / ...). Used to detect when
    /// the agent has exited so we can clean up the session — agents don't
    /// always fire SessionEnd reliably (Codex doesn't, for example).
    var agentPid: Int?

    /// Resolved provider object for theming/grouping.
    var provider: AIProvider { AIProvider.from(source) }

    var projectName: String {
        (cwd as NSString).lastPathComponent
    }

    /// Preferred display name. Falls through three sources in order:
    ///   1. `sessionTitle` — Claude Code sends this; Codex doesn't.
    ///   2. The folder name from `cwd` if it looks like a real project (not the
    ///      user's home directory).
    ///   3. The first prompt the user sent, truncated. Better than showing the
    ///      home-folder name when Codex was launched from `~`.
    var displayName: String {
        if let title = sessionTitle, !title.isEmpty { return title }
        if isMeaningfulProjectFolder { return projectName }
        if let prompt = firstPrompt, !prompt.isEmpty {
            return Self.truncated(prompt)
        }
        return projectName
    }

    /// True when `cwd` isn't the user's home directory and isn't `/` —
    /// i.e. it points at a project we'd want to show in the title slot.
    private var isMeaningfulProjectFolder: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return cwd != home && cwd != "/" && cwd != "~"
    }

    private static func truncated(_ s: String, max: Int = 40) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= max { return trimmed }
        return String(trimmed.prefix(max)) + "…"
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
