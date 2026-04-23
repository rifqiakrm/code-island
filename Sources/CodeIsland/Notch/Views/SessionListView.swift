import SwiftUI

struct SessionListView: View {
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var rateLimitStore: RateLimitStore
    @ObservedObject var settingsStore: SettingsStore
    let onCollapse: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Rate limits header bar + controls
            HStack(spacing: 8) {
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
            .padding(.vertical, 6)

            if sessionStore.activeSessions.isEmpty {
                // Empty state
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.3))
                    Text("No active sessions")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                    Text("Start Claude Code to begin")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
                Spacer()
            } else {
                // Session cards
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(
                            sessionStore.activeSessions.values.sorted(by: { $0.startedAt > $1.startedAt }),
                            id: \.id
                        ) { session in
                            // Show permission view inline for sessions needing approval
                            if session.pendingPermission != nil {
                                SessionCardView(session: session)
                            } else {
                                SessionCardView(session: session)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }

                // Footer: "Show all N sessions"
                Divider()
                    .background(Color.white.opacity(0.1))

                Button(action: onCollapse) {
                    Text("Show all \(sessionStore.sessions.count) sessions")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
