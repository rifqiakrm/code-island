import SwiftUI

/// 8-bit pixel art Claude Code mascot — matches the official terracotta design.
struct PixelMascot: View {
    var size: CGFloat = 2.0
    var palette: MascotPalette = .claude

    // 13x11 pixel grid — exact Claude Code mascot from official generator
    // B = body (1), D = dark eyes (2), . = transparent (0)
    static let pixels: [[Int]] = [
        [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
        [0, 0, 1, 1, 2, 1, 1, 1, 2, 1, 1, 0, 0],
        [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
        [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
        [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
        [0, 0, 1, 0, 1, 0, 0, 0, 1, 0, 1, 0, 0],
        [0, 0, 1, 0, 1, 0, 0, 0, 1, 0, 1, 0, 0],
    ]

    enum MascotPalette {
        case claude    // Terracotta/salmon (default)
        case thinking  // Cyan
        case idle      // Green
        case error     // Red

        var body: Color {
            switch self {
            case .claude: return Color(red: 0.83, green: 0.51, blue: 0.42)  // exact terracotta
            case .thinking: return Color(red: 0.30, green: 0.75, blue: 0.90)
            case .idle: return Color(red: 0.45, green: 0.78, blue: 0.45)
            case .error: return Color(red: 0.90, green: 0.35, blue: 0.30)
            }
        }

        var eyes: Color {
            switch self {
            case .claude: return Color(red: 0.18, green: 0.13, blue: 0.10)
            case .thinking: return Color(red: 0.08, green: 0.25, blue: 0.35)
            case .idle: return Color(red: 0.10, green: 0.25, blue: 0.12)
            case .error: return Color(red: 0.30, green: 0.08, blue: 0.08)
            }
        }
    }

    var body: some View {
        Canvas { context, _ in
            for (row, cols) in Self.pixels.enumerated() {
                for (col, pixel) in cols.enumerated() {
                    guard pixel > 0 else { continue }
                    let color = pixel == 2 ? palette.eyes : palette.body
                    let rect = CGRect(
                        x: CGFloat(col) * size,
                        y: CGFloat(row) * size,
                        width: size,
                        height: size
                    )
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(
            width: CGFloat(Self.pixels[0].count) * size,
            height: CGFloat(Self.pixels.count) * size
        )
    }
}

/// Animated mascot that picks palette based on session status
struct SessionMascot: View {
    let status: SessionStatus
    var size: CGFloat = 2.0
    var animated: Bool = true

    @State private var bounce = false

    var body: some View {
        PixelMascot(size: size, palette: paletteFor(status))
            .offset(y: animated && isActive ? (bounce ? -1.5 : 1.5) : 0)
            .scaleEffect(animated && isActive ? (bounce ? 1.05 : 0.95) : 1.0)
            .animation(
                isActive ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default,
                value: bounce
            )
            .onAppear {
                if isActive { bounce = true }
            }
            .onChange(of: status) { _, newStatus in
                bounce = newStatus == .thinking || newStatus == .toolUse
            }
    }

    private var isActive: Bool {
        status == .thinking || status == .toolUse
    }

    private func paletteFor(_ status: SessionStatus) -> PixelMascot.MascotPalette {
        switch status {
        case .thinking, .toolUse: return .thinking
        case .idle, .completed: return .claude
        case .error: return .error
        case .waitingPermission: return .claude
        }
    }
}
