import SwiftUI

struct PermissionView: View {
    let session: Session
    let permission: PendingPermission
    let onRespond: (PermissionAction) -> Void
    @ObservedObject var rateLimitStore: RateLimitStore
    @ObservedObject var settingsStore: SettingsStore
    let onOpenSettings: () -> Void
    let onToggleExpand: (Bool) -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top bar: rate limits + sound + gear
            HStack(spacing: 10) {
                RateLimitBar(rateLimitStore: rateLimitStore, provider: session.provider)
                Spacer()
                Button(action: { settingsStore.soundEnabled.toggle() }) {
                    Image(systemName: settingsStore.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(settingsStore.soundEnabled ? 0.6 : 0.3))
                }
                .buttonStyle(.plain)
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Session header + Needs approval badge
            HStack(spacing: 8) {
                SessionMascot(status: .waitingPermission, size: 18, provider: session.provider)
                Text(session.displayName)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                    Text("Needs approval")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.orange.opacity(0.15))
                )
                Spacer()
                if let effort = session.effortLevel {
                    EffortBadge(level: effort)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            // Tool pill + subtitle (color per tool type)
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Image(systemName: iconForTool(permission.toolName))
                        .font(.system(size: 10))
                    Text(permission.toolName)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundColor(colorForTool(permission.toolName))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(colorForTool(permission.toolName).opacity(0.15))
                )
                Text(subtitleForTool(permission.toolName))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.65))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            // File path / URL / pattern row (if available)
            if let path = permission.filePath {
                HStack(spacing: 7) {
                    Image(systemName: pathRowIcon(permission.toolName))
                        .font(.system(size: 11))
                        .foregroundColor(colorForTool(permission.toolName).opacity(0.8))
                    Text(pathRowLabel(permission.toolName))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .kerning(0.5)
                    Text(shortenPath(path))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }

            // Content preview (Write content, Edit diff, or command/description)
            if let preview = contentPreview() {
                VStack(spacing: 0) {
                    HStack {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.5))
                            Text(preview.label)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                                .kerning(0.5)
                        }
                        Spacer()
                        Text(preview.metric)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                        Button(action: {
                            isExpanded.toggle()
                            onToggleExpand(isExpanded)
                        }) {
                            Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                        .help(isExpanded ? "Collapse" : "Expand content")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8)
                            .fill(.white.opacity(0.08))
                    )

                    ScrollView {
                        Text(preview.attributed)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(10)
                    }
                    .frame(maxHeight: isExpanded ? 400 : 220)
                    .background(
                        UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                            .fill(.white.opacity(0.05))
                    )
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
                .padding(.horizontal, 14)
            }

            Spacer(minLength: 12)

            // 4 compact action buttons
            HStack(spacing: 6) {
                ActionButton(icon: "xmark", label: "Deny", hint: "", color: Color(red: 0.92, green: 0.55, blue: 0.55)) {
                    onRespond(.deny)
                }
                ActionButton(icon: "checkmark", label: "Allow Once", hint: "", color: Color(red: 0.45, green: 0.78, blue: 0.86)) {
                    onRespond(.allowOnce)
                }
                ActionButton(icon: "checkmark.circle", label: "Allow All", hint: "", color: Color(red: 0.55, green: 0.78, blue: 0.55)) {
                    onRespond(.allowAll)
                }
                ActionButton(icon: "bolt", label: "Bypass", hint: "", color: Color(red: 0.70, green: 0.62, blue: 0.92)) {
                    onRespond(.bypass)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func subtitleForTool(_ tool: String) -> String {
        switch tool.lowercased() {
        case "bash": return "wants to execute a shell command"
        case "read": return "wants to read a file"
        case "write": return "wants to write a file"
        case "edit", "multiedit": return "wants to edit a file"
        case "glob": return "wants to search for files"
        case "grep": return "wants to search code"
        case "webfetch": return "wants to fetch an external URL"
        case "websearch": return "wants to search the web"
        case "task", "agent": return "wants to run a subagent"
        default: return "wants to run \(tool)"
        }
    }

    private func colorForTool(_ tool: String) -> Color {
        switch tool.lowercased() {
        case "bash", "write": return Color(red: 1.0, green: 0.42, blue: 0.42)        // red
        case "edit", "multiedit": return Color(red: 1.0, green: 0.72, blue: 0.30)    // orange
        case "read", "webfetch": return Color(red: 0.30, green: 0.80, blue: 1.0)     // cyan
        case "grep", "glob", "websearch": return Color(red: 0.65, green: 0.55, blue: 0.98)  // purple
        case "task", "agent": return Color(red: 0.45, green: 0.78, blue: 0.45)       // green
        default: return Color(red: 1.0, green: 0.42, blue: 0.42)                     // red default
        }
    }

    private func iconForTool(_ tool: String) -> String {
        switch tool.lowercased() {
        case "bash": return "terminal.fill"
        case "read": return "doc.text.fill"
        case "write": return "doc.badge.plus"
        case "edit", "multiedit": return "pencil"
        case "glob", "grep": return "magnifyingglass"
        case "webfetch": return "globe"
        case "websearch": return "magnifyingglass.circle"
        default: return "wrench.fill"
        }
    }

    private func pathRowLabel(_ tool: String) -> String {
        switch tool.lowercased() {
        case "webfetch": return "url"
        case "grep", "glob": return "pattern"
        default: return "path"
        }
    }

    private func pathRowIcon(_ tool: String) -> String {
        switch tool.lowercased() {
        case "webfetch": return "link"
        case "grep", "glob": return "magnifyingglass"
        default: return "doc.text"
        }
    }

    private func shortenPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }

    private struct PreviewData {
        let label: String
        let metric: String
        let attributed: AttributedString
    }

    private func contentPreview() -> PreviewData? {
        // Edit tool: show colored diff using real file line numbers
        if let oldStr = permission.oldString, let newStr = permission.newString {
            let lines = newStr.components(separatedBy: "\n").count
            let oldLines = oldStr.components(separatedBy: "\n").count
            let startLine = permission.filePath.map { SyntaxHighlighter.findStartLine(filePath: $0, needle: oldStr) } ?? 1
            return PreviewData(
                label: "edit",
                metric: "−\(oldLines) +\(lines) lines",
                attributed: SyntaxHighlighter.diff(old: oldStr, new: newStr, startLine: startLine)
            )
        }
        // Write tool: show content with syntax highlighting (or WebFetch: show prompt plain)
        if let content = permission.content, !content.isEmpty {
            let tool = permission.toolName.lowercased()
            let isWebFetch = tool == "webfetch"
            let lines = content.components(separatedBy: "\n").count
            let bytes = content.utf8.count
            let attributed: AttributedString
            if isWebFetch {
                var s = AttributedString(content)
                s.foregroundColor = .white.opacity(0.85)
                attributed = s
            } else {
                attributed = SyntaxHighlighter.highlight(content, withLineNumbers: true, startLine: 1)
            }
            return PreviewData(
                label: isWebFetch ? "prompt" : "content",
                metric: isWebFetch ? "" : "\(lines) line\(lines == 1 ? "" : "s") · \(formatBytes(bytes))",
                attributed: attributed
            )
        }
        // Bash command or other: show description
        if let desc = permission.description, !desc.isEmpty, permission.filePath == nil {
            let isBash = permission.toolName.lowercased() == "bash"
            return PreviewData(
                label: isBash ? "command" : "input",
                metric: "",
                attributed: isBash ? SyntaxHighlighter.highlight(desc) : {
                    var s = AttributedString(desc)
                    s.foregroundColor = .white.opacity(0.85)
                    return s
                }()
            )
        }
        return nil
    }

    private func formatBytes(_ n: Int) -> String {
        if n >= 1024 { return String(format: "%.1fkB", Double(n) / 1024.0) }
        return "\(n)B"
    }
}

struct ActionButton: View {
    let icon: String
    let label: String
    let hint: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            .foregroundColor(color.opacity(0.95))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }
}
