import AppKit
import SwiftUI

/// A borderless, floating panel that sits in the notch area.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        configure()
    }

    private func configure() {
        // Transparency
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        // Visible on all spaces, doesn't hide
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        // Allow clicks without requiring activation first
        isMovable = false
        isMovableByWindowBackground = false
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false

        // Allow first-click interaction
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
    }

    /// Must be called AFTER orderFront to ensure level sticks.
    /// Vibe Island uses layer 27, just above the menu bar (25).
    func applyNotchLevel() {
        level = NSWindow.Level(rawValue: 27)
    }

    // Allow the panel to become key when user clicks (needed for buttons/gestures)
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Accept mouse events even when app is not active
    override func mouseDown(with event: NSEvent) {
        makeKey()
        super.mouseDown(with: event)
    }

    // Deliver first mouse click to the window without requiring activation
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            makeKeyAndOrderFront(nil)
        }
        super.sendEvent(event)
    }

    // Prevent macOS from constraining the window below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    // Mouse hover detection
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        NotificationCenter.default.post(name: .notchMouseMoved, object: event)
    }
}

/// NSHostingView subclass that accepts first mouse click without requiring activation.
final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension Notification.Name {
    static let notchMouseMoved = Notification.Name("notchMouseMoved")
    static let notchExpand = Notification.Name("notchExpand")
    static let notchCollapse = Notification.Name("notchCollapse")
}
