import Foundation
import Combine

/// One rate-limit window in the format the notch UI consumes.
/// Wraps `WindowUsage` (normalized 0…1 percent + optional reset time) with
/// the "Xh / Xm / Xd remaining" formatting the bar prints.
struct RateLimit {
    let usedPercentage: Int
    let resetsAt: Date

    var timeRemaining: String {
        let remaining = resetsAt.timeIntervalSinceNow
        guard remaining > 0 else { return "now" }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours >= 24 {
            return "\(hours / 24)d"
        }
        if hours > 0 {
            return "\(hours)h\(String(format: "%02d", minutes))m"
        }
        return "\(minutes)m"
    }

    init?(window: WindowUsage) {
        guard let reset = window.resetAt else { return nil }
        self.usedPercentage = window.percentInt
        self.resetsAt = reset
    }
}

/// Per-provider snapshot of rate-limit data + a human-readable error caption.
struct ProviderUsage {
    let fiveHour: RateLimit?
    let sevenDay: RateLimit?
    let plan: String?
    let error: String?

    static let empty = ProviderUsage(fiveHour: nil, sevenDay: nil, plan: nil, error: nil)
}

/// Fetches usage for every supported provider in parallel on a 5-minute timer
/// and publishes the latest snapshot for the UI. Replaces the old statusline
/// approach (Claude only, stale when Claude wasn't running) with live HTTP
/// fetches that work whether sessions are open or not.
@MainActor
final class RateLimitStore: ObservableObject {
    @Published private(set) var usage: [String: ProviderUsage] = [:]

    private var timer: Timer?
    private let refreshInterval: TimeInterval = 5 * 60  // 5 minutes

    init() {
        // Kick off an initial fetch and start the refresh timer.
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    deinit {
        timer?.invalidate()
    }

    /// Look up the latest cached snapshot for a provider.
    func snapshot(for provider: AIProvider) -> ProviderUsage {
        usage[provider.id] ?? .empty
    }

    func fiveHour(for provider: AIProvider) -> RateLimit? {
        usage[provider.id]?.fiveHour
    }

    func sevenDay(for provider: AIProvider) -> RateLimit? {
        usage[provider.id]?.sevenDay
    }

    /// Run all providers' fetchers concurrently and store the resulting snapshots.
    func refresh() async {
        async let claude = UsageFetcher.fetchClaude()
        async let codex  = UsageFetcher.fetchCodex()
        let (c, cx) = await (claude, codex)
        usage["claude"] = Self.snapshot(from: c)
        usage["codex"]  = Self.snapshot(from: cx)
    }

    private static func snapshot(from app: AppUsage) -> ProviderUsage {
        ProviderUsage(
            fiveHour: RateLimit(window: app.fiveHour),
            sevenDay: RateLimit(window: app.weekly),
            plan: app.plan,
            error: app.fiveHour.error ?? app.weekly.error
        )
    }
}
