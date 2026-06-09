import AppKit
import SwiftUI

extension Notification.Name {
    static let openSettings = Notification.Name("CodeIsland.openSettings")
}

final class MenuBarManager {
    private var statusItem: NSStatusItem?
    private let settingsStore: SettingsStore
    private let sessionStore: SessionStore
    private let onQuit: () -> Void
    private let onReloadSounds: () -> Void
    private var settingsWindow: NSWindow?

    init(settingsStore: SettingsStore, sessionStore: SessionStore, onReloadSounds: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.settingsStore = settingsStore
        self.sessionStore = sessionStore
        self.onReloadSounds = onReloadSounds
        self.onQuit = onQuit
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

        menu.addItem(withTitle: "Code Island", action: nil, keyEquivalent: "")
        menu.items.last?.isEnabled = false

        menu.addItem(NSMenuItem.separator())

        let sessionsItem = NSMenuItem(title: "No active sessions", action: nil, keyEquivalent: "")
        sessionsItem.isEnabled = false
        sessionsItem.tag = 100
        menu.addItem(sessionsItem)

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

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Code Island", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

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

        let view = SettingsView(settingsStore: settingsStore, onReloadSounds: onReloadSounds)
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
        HookInstaller.install()
    }

    @objc private func quit() {
        onQuit()
    }
}
