import Foundation
import Combine
import ServiceManagement

final class SettingsStore: ObservableObject {
    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }
    @Published var soundVolume: Float {
        didSet { UserDefaults.standard.set(soundVolume, forKey: "soundVolume") }
    }
    @Published var autoExpandOnPermission: Bool {
        didSet { UserDefaults.standard.set(autoExpandOnPermission, forKey: "autoExpandOnPermission") }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            updateLoginItem()
        }
    }
    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    /// Whether the user has seen the redesigned (themed, full-screen) onboarding.
    /// Separate from `hasCompletedOnboarding` so existing users — who already
    /// completed the OLD onboarding — get shown the new one once on update, then
    /// never again. Fresh installs see it via this flag being false too.
    @Published var hasSeenThemeOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasSeenThemeOnboarding, forKey: "hasSeenThemeOnboarding") }
    }

    /// Selected visual theme for the notch windows. Persisted by raw value.
    @Published var notchThemeID: NotchThemeID {
        didSet { UserDefaults.standard.set(notchThemeID.rawValue, forKey: "notchThemeID") }
    }

    /// Last app version for which we showed the "What's New" card. Shown once
    /// per version bump (returning users on update); fresh installs get
    /// onboarding instead and have this stamped to the current version.
    @Published var lastWhatsNewVersion: String {
        didSet { UserDefaults.standard.set(lastWhatsNewVersion, forKey: "lastWhatsNewVersion") }
    }

    /// Providers whose hooks are blanket "before every tool" gates (no native
    /// selective permission event). Strict-approval mode turns those into
    /// blocking in-notch approve/deny prompts — opt-in, per provider.
    static let strictApprovalProviders = ["gemini", "cursor", "copilot", "kimi", "antigravity"]

    /// Per-provider "review every action" flags (default off). Persisted to
    /// UserDefaults AND mirrored to ~/.code-island/config.json so the bridge
    /// (a separate process) can decide whether to block a `before*` hook.
    @Published var strictApproval: [String: Bool] {
        didSet { persistStrictApproval() }
    }

    // Per-sound toggles
    @Published var soundSessionStart: Bool {
        didSet { UserDefaults.standard.set(soundSessionStart, forKey: "soundSessionStart") }
    }
    @Published var soundCompletion: Bool {
        didSet { UserDefaults.standard.set(soundCompletion, forKey: "soundCompletion") }
    }
    @Published var soundToolUse: Bool {
        didSet { UserDefaults.standard.set(soundToolUse, forKey: "soundToolUse") }
    }
    @Published var soundError: Bool {
        didSet { UserDefaults.standard.set(soundError, forKey: "soundError") }
    }
    @Published var soundPermission: Bool {
        didSet { UserDefaults.standard.set(soundPermission, forKey: "soundPermission") }
    }

    init() {
        let defaults = UserDefaults.standard

        // Register defaults
        defaults.register(defaults: [
            "soundEnabled": true,
            "soundVolume": Float(0.7),
            "autoExpandOnPermission": true,
            "launchAtLogin": false,
            "hasCompletedOnboarding": false,
            "soundSessionStart": true,
            "soundCompletion": true,
            "soundToolUse": false,
            "soundError": true,
            "soundPermission": true,
            "notchThemeID": NotchThemeID.default.rawValue,
            "hasSeenThemeOnboarding": false,
        ])

        self.soundEnabled = defaults.bool(forKey: "soundEnabled")
        self.soundVolume = defaults.float(forKey: "soundVolume")
        self.autoExpandOnPermission = defaults.bool(forKey: "autoExpandOnPermission")
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        self.hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        self.soundSessionStart = defaults.bool(forKey: "soundSessionStart")
        self.soundCompletion = defaults.bool(forKey: "soundCompletion")
        self.soundToolUse = defaults.bool(forKey: "soundToolUse")
        self.soundError = defaults.bool(forKey: "soundError")
        self.soundPermission = defaults.bool(forKey: "soundPermission")
        self.notchThemeID = NotchThemeID(rawValue: defaults.string(forKey: "notchThemeID") ?? "") ?? .default
        self.hasSeenThemeOnboarding = defaults.bool(forKey: "hasSeenThemeOnboarding")
        self.lastWhatsNewVersion = defaults.string(forKey: "lastWhatsNewVersion") ?? ""

        if let data = defaults.data(forKey: "strictApproval"),
           let map = try? JSONDecoder().decode([String: Bool].self, from: data) {
            self.strictApproval = map
        } else {
            self.strictApproval = [:]
        }
        // Mirror to the bridge config on launch so it reflects the saved state.
        writeBridgeConfig()
    }

    /// Convenience accessor/mutator for the per-provider toggle.
    func isStrict(_ provider: String) -> Bool { strictApproval[provider] == true }
    func setStrict(_ provider: String, _ on: Bool) { strictApproval[provider] = on }

    private func persistStrictApproval() {
        if let data = try? JSONEncoder().encode(strictApproval) {
            UserDefaults.standard.set(data, forKey: "strictApproval")
        }
        writeBridgeConfig()
    }

    /// Writes ~/.code-island/config.json — the bridge reads this each run to
    /// decide whether to block a provider's `before*` hook for approval.
    private func writeBridgeConfig() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".code-island")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("config.json")
        let payload: [String: Any] = ["strictApproval": strictApproval]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func updateLoginItem() {
        let service = SMAppService.mainApp
        do {
            if launchAtLogin {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            print("[CodeIsland] Login item error: \(error)")
        }
    }
}
