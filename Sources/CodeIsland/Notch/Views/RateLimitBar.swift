import SwiftUI

struct RateLimitBar: View {
    @ObservedObject var rateLimitStore: RateLimitStore

    var body: some View {
        HStack(spacing: 4) {
            if let fh = rateLimitStore.fiveHour {
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

            if rateLimitStore.fiveHour != nil && rateLimitStore.sevenDay != nil {
                Text("|")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
            }

            if let sd = rateLimitStore.sevenDay {
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
        }
    }

    private func colorForPct(_ pct: Int) -> Color {
        if pct >= 80 { return .red }
        if pct >= 50 { return .orange }
        return .green
    }
}
