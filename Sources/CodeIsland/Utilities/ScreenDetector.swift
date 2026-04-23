import AppKit

struct ScreenDetector {
    /// Returns the screen that has a notch, or the main screen as fallback.
    static var notchScreen: NSScreen {
        // The built-in display with a notch has safeAreaInsets.top > 0
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// Whether the target screen has a hardware notch.
    static var hasNotch: Bool {
        notchScreen.safeAreaInsets.top > 0
    }

    /// The notch area height (menu bar height on notch Macs).
    static var notchHeight: CGFloat {
        notchScreen.safeAreaInsets.top
    }

    /// The approximate width of the hardware notch cutout.
    static var notchWidth: CGFloat {
        // On 14" MacBook Pro the notch is ~180pt wide, 16" is ~186pt.
        // We use a reasonable default; the panel is wider anyway.
        180
    }

    /// Frame for centering a notch panel on the target screen.
    /// The panel's top edge = screen top, so it overlaps the notch area.
    /// Content inside the panel adds top padding to sit below the physical notch.
    static func notchPanelFrame(panelSize: NSSize) -> NSRect {
        let screen = notchScreen
        let screenFrame = screen.frame
        let x = screenFrame.midX - panelSize.width / 2
        // Top of panel = top of screen (overlaps notch/menu bar)
        let y = screenFrame.maxY - panelSize.height
        return NSRect(origin: NSPoint(x: x, y: y), size: panelSize)
    }
}
