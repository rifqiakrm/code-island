import Foundation
import Combine

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
}

@MainActor
final class RateLimitStore: ObservableObject {
    @Published var fiveHour: RateLimit?
    @Published var sevenDay: RateLimit?

    private var timer: Timer?
    private let cacheFile: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        cacheFile = home.appendingPathComponent(".code-island/cache/rl.json")
        load()
        startPolling()
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.load()
            }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: cacheFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let fh = json["five_hour"] as? [String: Any],
           let pct = fh["used_percentage"] as? Int,
           let resets = fh["resets_at"] as? TimeInterval {
            fiveHour = RateLimit(usedPercentage: pct, resetsAt: Date(timeIntervalSince1970: resets))
        }

        if let sd = json["seven_day"] as? [String: Any],
           let pct = sd["used_percentage"] as? Int,
           let resets = sd["resets_at"] as? TimeInterval {
            sevenDay = RateLimit(usedPercentage: pct, resetsAt: Date(timeIntervalSince1970: resets))
        }
    }
}
