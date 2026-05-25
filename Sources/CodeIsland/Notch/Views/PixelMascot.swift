import SwiftUI
import Combine

/// Claude crab mascot — pixel-art crab with animated walking legs.
struct PixelMascot: View {
    var size: CGFloat = 16
    var palette: MascotPalette = .claude
    var animateLegs: Bool = false

    @State private var legPhase: Int = 0
    private let legTimer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    enum MascotPalette {
        case claude    // Terracotta/salmon (default)
        case thinking  // Cyan
        case idle      // Green
        case error     // Red
        case waiting   // Orange

        var body: Color {
            switch self {
            case .claude: return Color(red: 0.85, green: 0.47, blue: 0.34)
            case .thinking: return Color(red: 0.30, green: 0.75, blue: 0.90)
            case .idle: return Color(red: 0.45, green: 0.78, blue: 0.45)
            case .error: return Color(red: 0.90, green: 0.35, blue: 0.30)
            case .waiting: return Color(red: 1.0, green: 0.72, blue: 0.30)
            }
        }

        var eyes: Color { .black }
    }

    var body: some View {
        Canvas { context, canvasSize in
            let scale = size / 52.0
            let xOffset = (canvasSize.width - 66 * scale) / 2

            // Left antenna
            let leftAntenna = Path { p in
                p.addRect(CGRect(x: 0, y: 13, width: 6, height: 13))
            }.applying(CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: xOffset / scale, y: 0))
            context.fill(leftAntenna, with: .color(palette.body))

            // Right antenna
            let rightAntenna = Path { p in
                p.addRect(CGRect(x: 60, y: 13, width: 6, height: 13))
            }.applying(CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: xOffset / scale, y: 0))
            context.fill(rightAntenna, with: .color(palette.body))

            // Animated legs
            let baseLegPositions: [CGFloat] = [6, 18, 42, 54]
            let baseLegHeight: CGFloat = 13
            let legHeightOffsets: [[CGFloat]] = [
                [3, -3, 3, -3],
                [0, 0, 0, 0],
                [-3, 3, -3, 3],
                [0, 0, 0, 0],
            ]
            let currentHeightOffsets = animateLegs ? legHeightOffsets[legPhase % 4] : [CGFloat](repeating: 0, count: 4)

            for (index, xPos) in baseLegPositions.enumerated() {
                let heightOffset = currentHeightOffsets[index]
                let legHeight = baseLegHeight + heightOffset
                let leg = Path { p in
                    p.addRect(CGRect(x: xPos, y: 39, width: 6, height: legHeight))
                }.applying(CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: xOffset / scale, y: 0))
                context.fill(leg, with: .color(palette.body))
            }

            // Main body
            let body = Path { p in
                p.addRect(CGRect(x: 6, y: 0, width: 54, height: 39))
            }.applying(CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: xOffset / scale, y: 0))
            context.fill(body, with: .color(palette.body))

            // Left eye
            let leftEye = Path { p in
                p.addRect(CGRect(x: 12, y: 13, width: 6, height: 6.5))
            }.applying(CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: xOffset / scale, y: 0))
            context.fill(leftEye, with: .color(palette.eyes))

            // Right eye
            let rightEye = Path { p in
                p.addRect(CGRect(x: 48, y: 13, width: 6, height: 6.5))
            }.applying(CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: xOffset / scale, y: 0))
            context.fill(rightEye, with: .color(palette.eyes))
        }
        .frame(width: size * (66.0 / 52.0), height: size)
        .onReceive(legTimer) { _ in
            if animateLegs {
                legPhase = (legPhase + 1) % 4
            }
        }
    }
}

/// Animated mascot that picks palette based on session status
struct SessionMascot: View {
    let status: SessionStatus
    var size: CGFloat = 16
    var animated: Bool = true

    var body: some View {
        PixelMascot(
            size: size,
            palette: paletteFor(status),
            animateLegs: animated && isActive
        )
    }

    private var isActive: Bool {
        status == .thinking || status == .toolUse
    }

    private func paletteFor(_ status: SessionStatus) -> PixelMascot.MascotPalette {
        switch status {
        case .thinking, .toolUse: return .thinking
        case .idle, .completed: return .claude
        case .error: return .error
        case .waitingPermission: return .waiting
        }
    }
}
