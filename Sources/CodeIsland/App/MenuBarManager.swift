import AppKit
import SwiftUI

extension Notification.Name {
    static let openSettings = Notification.Name("CodeIsland.openSettings")
}

@MainActor
final class MenuBarManager: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let settingsStore: SettingsStore
    private let sessionStore: SessionStore
    private let updateChecker: UpdateChecker
    private let onQuit: () -> Void
    private let onReloadSounds: () -> Void
    private let onPreviewEvent: (SoundEvent) -> Void
    private let onPreviewFile: (String) -> Void
    private let onShowWhatsNew: () -> Void
    private var settingsWindow: NSWindow?

    init(settingsStore: SettingsStore, sessionStore: SessionStore, updateChecker: UpdateChecker, onReloadSounds: @escaping () -> Void, onPreviewEvent: @escaping (SoundEvent) -> Void, onPreviewFile: @escaping (String) -> Void, onShowWhatsNew: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.settingsStore = settingsStore
        self.sessionStore = sessionStore
        self.updateChecker = updateChecker
        self.onReloadSounds = onReloadSounds
        self.onPreviewEvent = onPreviewEvent
        self.onPreviewFile = onPreviewFile
        self.onShowWhatsNew = onShowWhatsNew
        self.onQuit = onQuit
        super.init()
        setupStatusItem()
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings), name: .openSettings, object: nil)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "Code Island")
            button.image?.size = NSSize(width: 16, height: 16)
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let titleItem = NSMenuItem(title: "Code Island v\(updateChecker.currentVersion)", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        // Sessions list — refreshed in menuWillOpen
        let sessionsHeader = NSMenuItem(title: "No active sessions", action: nil, keyEquivalent: "")
        sessionsHeader.isEnabled = false
        sessionsHeader.tag = TagSessions
        menu.addItem(sessionsHeader)

        menu.addItem(NSMenuItem.separator())

        let soundItem = NSMenuItem(title: "Sound Effects", action: #selector(toggleSound), keyEquivalent: "s")
        soundItem.target = self
        soundItem.state = settingsStore.soundEnabled ? .on : .off
        menu.addItem(soundItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let installItem = NSMenuItem(title: "Install Hooks", action: #selector(installHooks), keyEquivalent: "")
        installItem.target = self
        menu.addItem(installItem)

        let whatsNewItem = NSMenuItem(title: "What's New", action: #selector(showWhatsNew), keyEquivalent: "")
        whatsNewItem.target = self
        menu.addItem(whatsNewItem)

        let supportItem = NSMenuItem(title: "Support the project ♥", action: #selector(openSupport), keyEquivalent: "")
        supportItem.target = self
        menu.addItem(supportItem)

        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        updateItem.tag = TagUpdate
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Code Island", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    // MARK: - NSMenuDelegate

    /// Rebuild the sessions block right before the menu shows so the count
    /// reflects current state — the initial menu is built once and would
    /// otherwise stay frozen at "No active sessions".
    func menuWillOpen(_ menu: NSMenu) {
        refreshSessionsSection(menu: menu)
        refreshUpdateItem(menu: menu)
    }

    private func refreshSessionsSection(menu: NSMenu) {
        // Find the existing header item (tag 100) and remove it + any inserted children up to the next separator.
        guard let headerIdx = menu.items.firstIndex(where: { $0.tag == TagSessions }) else { return }
        // Remove any session entries we inserted previously (they have TagSessionEntry).
        let idx = headerIdx + 1
        while idx < menu.items.count && menu.items[idx].tag == TagSessionEntry {
            menu.removeItem(at: idx)
        }

        let active = Array(sessionStore.activeSessions.values).sorted(by: { $0.startedAt < $1.startedAt })
        let header = menu.items[headerIdx]
        if active.isEmpty {
            header.title = "No active sessions"
        } else {
            header.title = active.count == 1 ? "1 active session" : "\(active.count) active sessions"
            for (offset, session) in active.enumerated() {
                let name = session.displayName.isEmpty ? session.projectName : session.displayName
                let providerLabel = session.provider.displayName
                let item = NSMenuItem(title: "  \(providerLabel) · \(name)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                item.tag = TagSessionEntry
                menu.insertItem(item, at: headerIdx + 1 + offset)
            }
        }
    }

    private func refreshUpdateItem(menu: NSMenu) {
        guard let item = menu.items.first(where: { $0.tag == TagUpdate }) else { return }
        item.title = updateChecker.isChecking ? "Checking for Updates…" : "Check for Updates…"
        item.isEnabled = !updateChecker.isChecking
    }

    // Stable tags so we can find items when rebuilding sub-sections.
    private let TagSessions = 100
    private let TagSessionEntry = 101
    private let TagUpdate = 200

    @objc private func toggleSound() {
        settingsStore.soundEnabled.toggle()
        if let menu = statusItem?.menu,
           let item = menu.items.first(where: { $0.action == #selector(toggleSound) }) {
            item.state = settingsStore.soundEnabled ? .on : .off
        }
    }

    @objc private func openSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(settingsStore: settingsStore, updateChecker: updateChecker, onReloadSounds: onReloadSounds, onPreviewEvent: onPreviewEvent, onPreviewFile: onPreviewFile)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: view)
        window.title = "Code Island Settings"
        window.center()
        window.isReleasedWhenClosed = false
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func installHooks() {
        // Re-run the SAME full set the app installs on launch — Claude, Codex,
        // and all the descriptor-driven providers. (Previously this only did
        // Claude + Codex, silently skipping the other 15.)
        _ = HookInstaller.install()
        _ = CodexInstaller.install()
        _ = ProviderInstaller.installAll()

        let alert = NSAlert()
        alert.messageText = "Hooks installed"
        alert.informativeText = "Re-installed hooks for every detected agent. If an agent was already running, restart it to pick them up."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func checkForUpdates() {
        Task { @MainActor in
            await updateChecker.checkForUpdates(showNoUpdateAlert: true)
        }
    }

    @objc private func showWhatsNew() {
        onShowWhatsNew()
    }

    @objc private func openSupport() {
        if let url = URL(string: "https://ko-fi.com/rifqiakrm") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        onQuit()
    }
}
