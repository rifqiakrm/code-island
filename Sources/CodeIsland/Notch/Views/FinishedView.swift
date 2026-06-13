import SwiftUI

struct FinishedView: View {
    let session: Session
    let onDismiss: () -> Void
    @ObservedObject var rateLimitStore: RateLimitStore
    @ObservedObject var settingsStore: SettingsStore
    let onOpenSettings: () -> Void
    let onToggleExpand: (Bool) -> Void

    @Environment(\.notchTheme) private var theme
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top bar
            HStack(spacing: 10) {
                RateLimitBar(rateLimitStore: rateLimitStore, provider: session.provider)
                Spacer()
                Button(action: { settingsStore.soundEnabled.toggle() }) {
                    Image(systemName: settingsStore.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(settingsStore.soundEnabled ? 0.6 : 0.3))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Session header + Finished badge
            HStack(spacing: 8) {
                SessionMascot(status: .idle, size: 18, provider: session.provider)
                Text(session.displayName)
                    .font(theme.font(size: 13, weight: .bold))
                    .foregroundColor(.white)
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                    Text("Finished in \(session.durationText)")
                        .font(theme.font(size: 9, weight: .semibold))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .notchPill(theme, fill: .green.opacity(0.18))
                Spacer()
                if let effort = session.effortLevel {
                    EffortBadge(level: effort)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            // Tool pill (Done) + subtitle
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                    Text("Done")
                        .font(theme.font(size: 11, weight: .bold))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .notchPill(theme, fill: .green.opacity(0.15))
                Text("replied to your message")
                    .font(theme.font(size: 11))
                    .foregroundColor(.white.opacity(0.65))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            // User prompt row (like path row in permission)
            if let userMsg = session.lastUserMessage {
                HStack(spacing: 7) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 11))
                        .foregroundColor(theme.wellForeground.opacity(0.65))
                    Text("you")
                        .font(theme.font(size: 9, weight: .bold))
                        .foregroundColor(theme.wellForeground.opacity(0.5))
                        .kerning(0.5)
                    Text(userMsg)
                        .font(theme.font(size: 11))
                        .foregroundColor(theme.wellForeground.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .notchBox(theme)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }

            // Reply content card
            if let reply = session.lastAssistantMessage {
                VStack(spacing: 0) {
                    HStack {
                        HStack(spacing: 5) {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 9))
                                .foregroundColor(.green.opacity(0.7))
                            Text("reply")
                                .font(theme.font(size: 9, weight: .bold))
                                .foregroundColor(theme.wellForeground.opacity(0.5))
                                .kerning(0.5)
                        }
                        Spacer()
                        Text(replyMetric(reply))
                            .font(theme.font(size: 9))
                            .foregroundColor(theme.wellForeground.opacity(0.4))
                        Button(action: {
                            isExpanded.toggle()
                            onToggleExpand(isExpanded)
                        }) {
                            Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(theme.wellForeground.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        UnevenRoundedRectangle(topLeadingRadius: theme.boxRadius, topTrailingRadius: theme.boxRadius)
                            .fill(theme.boxFill)
                    )

                    ScrollView {
                        Text(reply)
                            .font(theme.font(size: 11))
                            .foregroundColor(theme.wellForeground.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(10)
                    }
                    .frame(maxHeight: isExpanded ? 400 : 240)
                    .background(
                        UnevenRoundedRectangle(bottomLeadingRadius: theme.boxRadius, bottomTrailingRadius: theme.boxRadius)
                            .fill(theme.boxFill)
                    )
                }
                .overlay(
                    RoundedRectangle(cornerRadius: theme.boxRadius, style: .continuous)
                        .strokeBorder(theme.boxStroke, lineWidth: 1)
                )
                .padding(.horizontal, 14)
            }

            Spacer(minLength: 10)

            // Dismiss button (full width, green)
            Button(action: onDismiss) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Dismiss")
                        .font(theme.font(size: 11, weight: .semibold))
                }
                .foregroundColor(.green.opacity(0.95))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .notchButton(theme, fill: .green.opacity(0.1), stroke: .green.opacity(0.35))
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Tap card body → jump to the terminal. The chrome buttons (sound,
        // gear, Dismiss) have explicit `.contentShape(Rectangle())` on
        // their labels so SwiftUI's hit testing routes taps to them
        // before falling through to this outer gesture (issue #28 was
        // about near-misses absorbing into the outer; we now make the
        // button hit zones explicit instead of removing the outer).
        .contentShape(Rectangle())
        .onTapGesture {
            TerminalJumper.jump(to: session)
        }
    }

    private func replyMetric(_ reply: String) -> String {
        let lines = reply.components(separatedBy: "\n").count
        let bytes = reply.utf8.count
        let lineLabel = "\(lines) line\(lines == 1 ? "" : "s")"
        let byteLabel = bytes >= 1024 ? String(format: "%.1fkB", Double(bytes) / 1024.0) : "\(bytes)B"
        return "\(lineLabel) · \(byteLabel)"
    }
}
