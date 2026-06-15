import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchWindowController: NotchWindowController?
    private var menuBarManager: MenuBarManager?
    private var onboardingController: OnboardingWindowController?
    private var whatsNewController: WhatsNewWindowController?
    private let sessionStore = SessionStore()
    private let socketServer = SocketServer()
    private let soundEngine = SoundEngine()
    private let settingsStore = SettingsStore()
    private let rateLimitStore = RateLimitStore()
    private let codexAppServer = CodexAppServerClient()
    private let updateChecker = UpdateChecker()
    private var cancellables = Set<AnyCancellable>()

    private func log(_ msg: String) {
        let line = "[\(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))] \(msg)\n"
        let logFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".code-island/debug.log")
        if let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? line.write(to: logFile, atomically: true, encoding: .utf8)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("App launching...")
        // Hide dock icon (LSUIElement backup)
        NSApp.setActivationPolicy(.accessory)

        // Wire up socket → session store → sound
        socketServer.onMessage = { [weak self] message, respond, respondRaw in
            DispatchQueue.main.async {
                guard let self else { return }
                self.log("Received: \(message.hookEvent) session=\(message.sessionId.prefix(8))")
                self.sessionStore.handleMessage(message, respond: respond, respondRaw: respondRaw)
            }
        }

        sessionStore.onEvent
            .sink { [weak self] event in
                self?.soundEngine.play(event)
                self?.notchWindowController?.handleSessionEvent(event)
            }
            .store(in: &cancellables)

        // Sync sound settings
        settingsStore.$soundEnabled
            .sink { [weak self] enabled in self?.soundEngine.setEnabled(enabled) }
            .store(in: &cancellables)
        settingsStore.$soundVolume
            .sink { [weak self] volume in self?.soundEngine.setVolume(volume) }
            .store(in: &cancellables)
        // Per-event sound assignments (Default / Off / a library file). The
        // @Published publisher emits the current value on subscribe, so this
        // also applies the initial assignments at startup.
        settingsStore.$soundAssignments
            .sink { [weak self] map in self?.soundEngine.applyAssignments(map) }
            .store(in: &cancellables)

        // Create notch window
        notchWindowController = NotchWindowController(
            sessionStore: sessionStore,
            settingsStore: settingsStore,
            rateLimitStore: rateLimitStore
        )
        notchWindowController?.showWindow(nil)
        let screen = ScreenDetector.notchScreen
        log("Notch window shown, frame: \(notchWindowController?.window?.frame ?? .zero)")
        log("Screen frame: \(screen.frame)")
        log("Screen visibleFrame: \(screen.visibleFrame)")
        log("SafeAreaInsets: top=\(screen.safeAreaInsets.top) bottom=\(screen.safeAreaInsets.bottom)")
        log("Notch height: \(ScreenDetector.notchHeight), hasNotch: \(ScreenDetector.hasNotch)")
        log("Window level: \(notchWindowController?.window?.level.rawValue ?? -1)")

        // Menu bar
        menuBarManager = MenuBarManager(
            settingsStore: settingsStore,
            sessionStore: sessionStore,
            updateChecker: updateChecker,
            onReloadSounds: { [weak self] in self?.soundEngine.reloadSounds() },
            onPreviewEvent: { [weak self] ev in self?.soundEngine.preview(ev) },
            onPreviewFile: { [weak self] name in self?.soundEngine.previewFile(name) },
            onShowWhatsNew: { [weak self] in self?.showWhatsNew() },
            onQuit: { NSApp.terminate(nil) }
        )

        // Start socket server
        socketServer.start()
        log("Socket server started")

        // Setup directories
        setupDirectories()

        // Auto-install hooks for every supported provider on every launch.
        // Installers are idempotent and pre-stage Codex config even if the user
        // doesn't have Codex installed yet, so it "just works" when they add it.
        Task.detached {
            _ = HookInstaller.install()
            _ = CodexInstaller.install()
            // Gemini, Qwen, Qoder, Factory, CodeBuddy, Cursor, Copilot — each
            // installed only if its config dir is present (Factory bootstraps).
            _ = ProviderInstaller.installAll()
        }

        // Subscribe SessionStore to Codex app-server thread stream. This both
        // surfaces resumed sessions immediately (Codex doesn't fire
        // SessionStart hooks on resume — they only fire on the first prompt)
        // and propagates user-renamed session titles.
        codexAppServer.$threads
            .sink { [weak self] threads in
                self?.sessionStore.applyCodexThreads(threads)
            }
            .store(in: &cancellables)
        // Critical for Codex cleanup: thread/closed from the daemon is the
        // only reliable end-of-session signal (hooks go through the daemon
        // process, so PID-based detection never fires).
        codexAppServer.closedThreadIds
            .sink { [weak self] threadId in
                self?.sessionStore.handleCodexThreadClosed(threadId)
            }
            .store(in: &cancellables)
        codexAppServer.start()

        // Show the (redesigned) onboarding when the user hasn't seen it yet —
        // fresh installs AND existing users updating into this version. Gated on
        // its own flag so it shows exactly once, never again on later updates.
        if !settingsStore.hasSeenThemeOnboarding {
            showOnboarding()
            // Fresh-install onboarding already covers everything — don't also
            // pop What's New; stamp the current version so it's considered seen.
            settingsStore.lastWhatsNewVersion = updateChecker.currentVersion
        } else if settingsStore.lastWhatsNewVersion != updateChecker.currentVersion {
            // Returning user who just updated → show the What's New highlights.
            showWhatsNew()
        }

        // Auto update check — silent unless a newer release is found. Checks
        // shortly after launch, then re-evaluates every few hours so a
        // long-running menu-bar session still gets a daily check (the check is
        // gated to at most once/day internally).
        Task {
            // Delay a few seconds so the notch is up and the user isn't
            // greeted by a popup the instant they launch.
            try? await Task.sleep(for: .seconds(8))
            await updateChecker.checkOnLaunchIfDue()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6 * 60 * 60))
                await updateChecker.checkOnLaunchIfDue()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        socketServer.stop()
        cleanupPidFile()
    }

    private func setupDirectories() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dirs = [
            home.appendingPathComponent(".code-island/bin"),
            home.appendingPathComponent(".code-island/run"),
            home.appendingPathComponent(".code-island/cache"),
            home.appendingPathComponent(".code-island/sound-packs"),
        ]
        for dir in dirs {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        // Write PID
        let pidFile = home.appendingPathComponent(".code-island/run/code-island.pid")
        try? "\(ProcessInfo.processInfo.processIdentifier)".write(to: pidFile, atomically: true, encoding: .utf8)
    }

    private func showOnboarding() {
        onboardingController = OnboardingWindowController(
            settingsStore: settingsStore,
            onComplete: { [weak self] in
                self?.onboardingController = nil
            }
        )
        onboardingController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showWhatsNew() {
        whatsNewController = WhatsNewWindowController(
            version: updateChecker.currentVersion,
            onClose: { [weak self] in
                guard let self else { return }
                self.settingsStore.lastWhatsNewVersion = self.updateChecker.currentVersion
                self.whatsNewController = nil
            }
        )
        whatsNewController?.showWindow(nil)
    }

    private func cleanupPidFile() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let pidFile = home.appendingPathComponent(".code-island/run/code-island.pid")
        try? FileManager.default.removeItem(at: pidFile)
    }
}
