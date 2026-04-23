import SwiftUI

struct PermissionView: View {
    let session: Session
    let permission: PendingPermission
    let onRespond: (PermissionAction) -> Void
    @ObservedObject var rateLimitStore: RateLimitStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                RateLimitBar(rateLimitStore: rateLimitStore)
                Spacer()
            }
            .padding(.top, 8)
            .padding(.horizontal, 10)

            // Session header (same as card)
            HStack(spacing: 8) {
                SessionMascot(status: .waitingPermission, size: 3.0)

                Text(session.projectName)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)

                if let prompt = session.firstPrompt {
                    Text("·")
                        .foregroundColor(.white.opacity(0.3))
                    Text(prompt)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 4) {
                    BadgePill(text: "Claude", color: .orange)
                    BadgePill(text: session.detectedTerminalApp, color: .blue)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Last user message
            if let userMsg = session.lastUserMessage {
                HStack(spacing: 4) {
                    Text("You:")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                    Text(userMsg)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }

            // Tool warning banner
            HStack(spacing: 6) {
                Image(systemName: iconForTool(permission.toolName))
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                Text(permission.toolName)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.orange)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08))

            // Tool input / diff preview
            if let desc = permission.description {
                ScrollView {
                    Text(desc)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 120)
                .background(Color.white.opacity(0.04))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }

            Spacer(minLength: 4)

            // 4 action buttons matching Vibe Island
            HStack(spacing: 8) {
                PermissionButton(title: "Deny", color: .gray) {
                    onRespond(.deny)
                }
                PermissionButton(title: "Allow Once", color: .blue) {
                    onRespond(.allowOnce)
                }
                PermissionButton(title: "Allow All", color: .green) {
                    onRespond(.allowAll)
                }
                PermissionButton(title: "Bypass", color: .red) {
                    onRespond(.bypass)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func iconForTool(_ tool: String) -> String {
        switch tool.lowercased() {
        case "bash": return "terminal.fill"
        case "read": return "doc.text"
        case "write": return "doc.fill"
        case "edit": return "pencil"
        case "glob": return "magnifyingglass"
        case "grep": return "text.magnifyingglass"
        case "agent": return "person.2"
        default: return "wrench"
        }
    }
}

struct PermissionButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color.opacity(0.6))
                )
        }
        .buttonStyle(.plain)
    }
}
