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
