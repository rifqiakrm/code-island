import SwiftUI

/// Compact rate-limit bar. Renders the 5h and 7d windows for a single provider
/// — pass `.claude` or `.codex` to switch. Caller decides which provider to
/// show (typically follows the active filter or the latest active session).
struct RateLimitBar: View {
    @ObservedObject var rateLimitStore: RateLimitStore
    /// Which provider's windows to render. Defaults to Claude for backward
    /// compatibility with views that haven't been wired to the filter yet.
    var provider: AIProvider = .claude
    /// Optional tap handler — when set, the bar becomes a button that cycles
    /// to the next provider. Used in SessionListView to let users flip
    /// between Claude / Codex rate limits without touching the filter chips.
    var onTap: (() -> Void)? = nil

    var body: some View {
        let snapshot = rateLimitStore.snapshot(for: provider)
        HStack(spacing: 5) {
            // Provider logo up front — disambiguates whose rate limit this is.
            ProviderIcon(provider: provider, size: 12)

            if let fh = snapshot.fiveHour {
                Text("5h")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                Text("\(fh.usedPercentage)%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(colorForPct(fh.usedPercentage))
                Text(fh.timeRemaining)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }

            if snapshot.fiveHour != nil && snapshot.sevenDay != nil {
                Text("|")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
            }

            if let sd = snapshot.sevenDay {
                Text("7d")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                Text("\(sd.usedPercentage)%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(colorForPct(sd.usedPercentage))
                Text(sd.timeRemaining)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }

            // No data yet (auth error, no token, still loading). Surface a
            // compact hint instead of an empty row so users know why it's blank.
            if snapshot.fiveHour == nil && snapshot.sevenDay == nil {
                Text(snapshot.error ?? "—")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }

    private func colorForPct(_ pct: Int) -> Color {
        if pct >= 90 { return .red }
        if pct >= 70 { return .orange }
        if pct >= 50 { return .yellow }
        return .green
    }
}
