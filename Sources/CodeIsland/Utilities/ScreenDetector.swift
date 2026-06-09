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

    /// The actual width of the hardware notch cutout, detected from the screen's
    /// auxiliary top areas (the menu-bar regions on either side of the notch).
    /// Falls back to a sensible default if the auxiliary areas aren't reported.
    static var notchWidth: CGFloat {
        let screen = notchScreen
        let totalWidth = screen.frame.width
        let leftWidth = screen.auxiliaryTopLeftArea?.width ?? 0
        let rightWidth = screen.auxiliaryTopRightArea?.width ?? 0
        if leftWidth > 0 && rightWidth > 0 {
            // The gap between the two auxiliary areas IS the notch cutout
            return max(160, totalWidth - leftWidth - rightWidth)
        }
        return 180
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
