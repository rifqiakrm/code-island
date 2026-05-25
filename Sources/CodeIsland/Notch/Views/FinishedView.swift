import SwiftUI

struct FinishedView: View {
    let session: Session
    let onDismiss: () -> Void
    @ObservedObject var rateLimitStore: RateLimitStore
    @ObservedObject var settingsStore: SettingsStore
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top bar
            HStack(spacing: 10) {
                RateLimitBar(rateLimitStore: rateLimitStore)
                Spacer()
                Button(action: { settingsStore.soundEnabled.toggle() }) {
                    Image(systemName: settingsStore.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(settingsStore.soundEnabled ? 0.6 : 0.3))
                }
                .buttonStyle(.plain)
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Session header + Finished badge
            HStack(spacing: 8) {
                SessionMascot(status: .idle, size: 18)
                Text(session.displayName)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                    Text("Finished in \(session.durationText)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.green.opacity(0.18))
                )
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
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.green.opacity(0.15))
                )
                Text("replied to your message")
                    .font(.system(size: 11, design: .monospaced))
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
                        .foregroundColor(.white.opacity(0.65))
                    Text("you")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .kerning(0.5)
                    Text(userMsg)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.tail)
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

            // Reply content card
            if let reply = session.lastAssistantMessage {
                VStack(spacing: 0) {
                    HStack {
                        HStack(spacing: 5) {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 9))
                                .foregroundColor(.green.opacity(0.7))
                            Text("reply")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                                .kerning(0.5)
                        }
                        Spacer()
                        Text(replyMetric(reply))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8)
                            .fill(.white.opacity(0.08))
                    )

                    ScrollView {
                        Text(reply)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(10)
                    }
                    .frame(maxHeight: 240)
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

            Spacer(minLength: 10)

            // Dismiss button (full width, green)
            Button(action: onDismiss) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Dismiss")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                .foregroundColor(.green.opacity(0.95))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.green.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(.green.opacity(0.35), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
