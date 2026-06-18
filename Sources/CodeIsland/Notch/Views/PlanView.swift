import SwiftUI

/// Claude's ExitPlanMode review. Instead of dumping the raw `{"plan":…}` JSON
/// through the generic permission card, this renders the proposed plan as
/// markdown (like the Finished card) and offers plan-shaped actions:
/// approve (exit into manual mode), approve & auto-run (acceptEdits), keep
/// planning (deny), or answer in terminal (defer "ask"). The action → response
/// mapping lives in SessionStore's PermissionRequest branch; plain `allow`
/// keeps the session in plan mode, so approve carries a `setMode`.
struct PlanView: View {
    let session: Session
    let permission: PendingPermission
    let onRespond: (PermissionAction) -> Void
    @ObservedObject var rateLimitStore: RateLimitStore
    @ObservedObject var settingsStore: SettingsStore
    let onOpenSettings: () -> Void

    @Environment(\.notchTheme) private var theme

    private let planAccent = Color(red: 0.55, green: 0.70, blue: 0.98)   // indigo
    private let approveColor = Color(red: 0.55, green: 0.78, blue: 0.55) // green
    private let autoColor = Color(red: 0.96, green: 0.72, blue: 0.25)    // amber (matches "auto mode on")
    private let denyColor = Color(red: 0.92, green: 0.55, blue: 0.55)    // red

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

            // Session header + "Plan ready" badge
            HStack(spacing: 8) {
                SessionMascot(status: .waitingPermission, size: 18, provider: session.provider)
                Text(session.displayName)
                    .font(theme.font(size: 13, weight: .bold))
                    .foregroundColor(.white)
                HStack(spacing: 4) {
                    Image(systemName: "checklist")
                        .font(.system(size: 9))
                    Text("Plan ready")
                        .font(theme.font(size: 9, weight: .semibold))
                }
                .foregroundColor(planAccent)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .notchPill(theme, fill: planAccent.opacity(0.15))
                Spacer()
                if let effort = session.effortLevel {
                    EffortBadge(level: effort)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            // Plan, rendered as markdown (scrollable)
            VStack(spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 9))
                        .foregroundColor(theme.wellForeground.opacity(0.5))
                    Text("plan")
                        .font(theme.font(size: 9, weight: .bold))
                        .foregroundColor(theme.wellForeground.opacity(0.5))
                        .kerning(0.5)
                    Spacer()
                    if let path = permission.planFilePath {
                        Text(shortenPath(path))
                            .font(theme.font(size: 9))
                            .foregroundColor(theme.wellForeground.opacity(0.4))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: theme.boxRadius, topTrailingRadius: theme.boxRadius)
                        .fill(theme.boxFill)
                )

                ScrollView {
                    MarkdownText(
                        text: permission.planMarkdown ?? "",
                        color: theme.wellForeground.opacity(0.9),
                        codeBackground: theme.lightWells ? .black.opacity(0.07) : .black.opacity(0.35)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
                .frame(maxHeight: .infinity)
                .background(
                    UnevenRoundedRectangle(bottomLeadingRadius: theme.boxRadius, bottomTrailingRadius: theme.boxRadius)
                        .fill(theme.boxFill)
                )
            }
            .overlay(
                RoundedRectangle(cornerRadius: theme.boxRadius, style: .continuous)
                    .strokeBorder(theme.boxStroke, lineWidth: theme.strokeWidth)
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            Divider().background(Color.white.opacity(0.08))

            // Actions — two rows: prominent approves, then secondary escape hatches.
            VStack(spacing: 8) {
                // Order mirrors Claude's own plan prompt: "Yes, and use auto
                // mode" first, then "Yes, manually approve edits".
                HStack(spacing: 6) {
                    ActionButton(icon: "forward.fill", label: "Approve & auto mode", hint: "", color: autoColor) {
                        onRespond(.approvePlanAuto)
                    }
                    ActionButton(icon: "pencil", label: "Approve & manual edits", hint: "", color: approveColor) {
                        onRespond(.approvePlan)
                    }
                }
                HStack(spacing: 10) {
                    Button(action: { onRespond(.deferToApp) }) {
                        HStack(spacing: 7) {
                            Image(systemName: "terminal")
                                .font(.system(size: 12))
                            Text("Answer in terminal")
                                .font(theme.font(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .notchButton(theme, fill: .white.opacity(0.06), stroke: .white.opacity(0.18))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(action: { onRespond(.deny) }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 11))
                            Text("Keep planning")
                                .font(theme.font(size: 11, weight: .semibold))
                        }
                        .foregroundColor(denyColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .notchButton(theme, fill: denyColor.opacity(0.12), stroke: denyColor.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func shortenPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }
}
