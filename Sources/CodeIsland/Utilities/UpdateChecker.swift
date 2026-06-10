import Foundation
import AppKit

/// Checks GitHub releases for a newer version. Runs silently on launch (at
/// most once per week) and can be triggered manually from Settings. Anonymous
/// — uses the public Releases API, no auth or telemetry.
@MainActor
final class UpdateChecker: ObservableObject {
    private let releaseURL = URL(string: "https://api.github.com/repos/rifqiakrm/code-island/releases/latest")!
    private let releasePageURL = URL(string: "https://github.com/rifqiakrm/code-island/releases/latest")!

    @Published var latestVersion: String? = nil
    @Published var lastCheckedAt: Date? = nil
    @Published var isChecking: Bool = false
    @Published var lastError: String? = nil

    private let defaults = UserDefaults.standard
    private let lastCheckKey = "updateChecker.lastCheckedAt"
    private let lastSeenKey = "updateChecker.lastSeenVersion"
    private let autoCheckKey = "updateChecker.autoCheckEnabled"

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    var autoCheckEnabled: Bool {
        get { defaults.object(forKey: autoCheckKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: autoCheckKey); objectWillChange.send() }
    }

    init() {
        if let date = defaults.object(forKey: lastCheckKey) as? Date {
            lastCheckedAt = date
        }
    }

    /// Called from AppDelegate at launch. Only runs if auto-check is on and
    /// the last check was > 7 days ago. Silent: no popup if nothing's new.
    func checkOnLaunchIfDue() async {
        guard autoCheckEnabled else { return }
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        if let last = lastCheckedAt, last > weekAgo { return }
        await checkForUpdates(showNoUpdateAlert: false)
    }

    /// Hits the GitHub Releases API, compares the tag to the bundle version,
    /// stores the result, and surfaces an NSAlert when a newer release exists.
    /// `showNoUpdateAlert: true` is the manual "Check now" path — informs the
    /// user even when they're up to date.
    func checkForUpdates(showNoUpdateAlert: Bool) async {
        isChecking = true
        lastError = nil
        defer { isChecking = false }
        do {
            var req = URLRequest(url: releaseURL, timeoutInterval: 12)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("code-island/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                lastError = "Couldn't reach GitHub Releases."
                if showNoUpdateAlert { showAlert(title: "Update check failed", body: lastError ?? "") }
                return
            }
            let parsed = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let tag = stripV(parsed.tagName)
            latestVersion = tag
            // Persist lastCheckedAt only on a fully successful fetch. A
            // single flaky-network launch would otherwise suppress update
            // notifications for the entire 7-day cadence (issue #34).
            lastCheckedAt = Date()
            defaults.set(Date(), forKey: lastCheckKey)
            if Self.isNewer(latest: tag, current: currentVersion) {
                // Always notify on a new version. Suppress only if user
                // already dismissed THIS specific version.
                let lastSeen = defaults.string(forKey: lastSeenKey) ?? ""
                if !showNoUpdateAlert && lastSeen == tag {
                    return  // they've seen it; don't nag again until next release
                }
                presentUpdateAlert(latest: tag, body: parsed.body ?? "")
            } else if showNoUpdateAlert {
                showAlert(
                    title: "You're up to date",
                    body: "Code Island \(currentVersion) is the latest version."
                )
            }
        } catch {
            lastError = error.localizedDescription
            if showNoUpdateAlert { showAlert(title: "Update check failed", body: lastError ?? "") }
        }
    }

    // MARK: - Version compare

    /// Strip a leading "v" so we can compare "1.0.1" to "v1.0.1" uniformly.
    private func stripV(_ s: String) -> String {
        s.hasPrefix("v") || s.hasPrefix("V") ? String(s.dropFirst()) : s
    }

    /// SemVer-aware version comparison. Splits each version on `-` into a
    /// numeric core (`MAJOR.MINOR.PATCH`) and an optional pre-release tail.
    /// Core segments compare numerically (so "1.10.0" > "1.9.0"). When the
    /// cores tie, a version *without* a pre-release tail outranks one
    /// with — `1.0.0` > `1.0.0-beta`, and `1.0.0-beta` is NOT newer than
    /// `1.0.0` (issue #21).
    static func isNewer(latest: String, current: String) -> Bool {
        func split(_ s: String) -> (core: String, pre: String?) {
            if let dashIdx = s.firstIndex(of: "-") {
                let core = String(s[..<dashIdx])
                let pre = String(s[s.index(after: dashIdx)...])
                return (core, pre.isEmpty ? nil : pre)
            }
            return (s, nil)
        }

        let (lCore, lPre) = split(latest)
        let (cCore, cPre) = split(current)

        // Compare cores segment by segment, numerically when possible.
        let lp = lCore.split(separator: ".").map(String.init)
        let cp = cCore.split(separator: ".").map(String.init)
        for i in 0..<max(lp.count, cp.count) {
            let l = i < lp.count ? lp[i] : "0"
            let c = i < cp.count ? cp[i] : "0"
            if let li = Int(l), let ci = Int(c) {
                if li != ci { return li > ci }
            } else if l != c {
                return l > c
            }
        }
        // Cores equal — handle pre-release precedence
        switch (lPre, cPre) {
        case (nil, nil):  return false              // 1.0.0 vs 1.0.0
        case (nil, _):    return true               // 1.0.0 vs 1.0.0-beta → latest is newer
        case (_, nil):    return false              // 1.0.0-beta vs 1.0.0 → pre-release is NOT newer
        case let (l?, c?): return l > c             // identifier compare
        }
    }

    // MARK: - Alerts

    private func presentUpdateAlert(latest: String, body: String) {
        let alert = NSAlert()
        alert.messageText = "Code Island \(latest) is available"
        alert.informativeText = "You're on \(currentVersion). Update for the latest fixes and features."
        alert.addButton(withTitle: "Open Releases")
        alert.addButton(withTitle: "Remind Me Later")
        alert.addButton(withTitle: "Skip This Version")
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(releasePageURL)
        case .alertThirdButtonReturn:
            // Suppress popups for this version until a newer one releases
            defaults.set(latest, forKey: lastSeenKey)
        default:
            break  // "Later" — pop up again on next weekly check
        }
    }

    private func showAlert(title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// User-facing convenience for opening the releases page.
    func openReleasesPage() {
        NSWorkspace.shared.open(releasePageURL)
    }

    // MARK: - GitHub Release schema

    private struct GitHubRelease: Decodable {
        let tagName: String
        let body: String?
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body
        }
    }
}
