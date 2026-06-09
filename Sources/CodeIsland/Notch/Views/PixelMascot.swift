import SwiftUI
import Combine

/// Pixel-art mascot view. The drawing routine is chosen by `shape` — each
/// provider gets its own silhouette (crab for Claude, box for Codex, ...).
struct PixelMascot: View {
    var size: CGFloat = 16
    var palette: MascotPalette = .claude
    var shape: MascotShape = .crab
    var animate: Bool = false

    @State private var animPhase: Int = 0
    private let animTimer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    enum MascotShape {
        case crab    // Claude — antennae + 4 walking legs + body + 2 eyes
        case box     // Codex — chunky cube with head bump + 1 eye + 2 stubby feet
        case sparkle // Gemini — diamond/sparkle silhouette (placeholder)
    }

    enum MascotPalette {
        // Idle / branded
        case claude
        case codex
        case gemini
        // Brand-tinted "active" palettes (thinking / using a tool)
        case claudeActive
        case codexActive
        case geminiActive
        // Universal semantic palettes
        case error
        case waiting

        var body: Color {
            switch self {
            case .claude:        return Color(red: 0.85, green: 0.47, blue: 0.34)
            case .codex:         return Color(red: 0.92, green: 0.92, blue: 0.92)
            case .gemini:        return Color(red: 0.55, green: 0.62, blue: 1.00)
            case .claudeActive:  return Color(red: 0.30, green: 0.75, blue: 0.90)  // cyan
            case .codexActive:   return Color(red: 0.60, green: 0.85, blue: 1.00)  // bright sky blue
            case .geminiActive:  return Color(red: 0.72, green: 0.55, blue: 1.00)  // purple
            case .error:         return Color(red: 0.90, green: 0.35, blue: 0.30)
            case .waiting:       return Color(red: 1.00, green: 0.72, blue: 0.30)
            }
        }

        var eyes: Color { .black }
    }

    var body: some View {
        Canvas { context, canvasSize in
            switch shape {
            case .crab:    drawCrab(context: context, canvasSize: canvasSize)
            case .box:     drawBox(context: context, canvasSize: canvasSize)
            case .sparkle: drawSparkle(context: context, canvasSize: canvasSize)
            }
        }
        .frame(width: aspectAdjustedWidth, height: size)
        .onReceive(animTimer) { _ in
            if animate { animPhase = (animPhase + 1) % 4 }
        }
    }

    private var aspectAdjustedWidth: CGFloat {
        switch shape {
        case .crab:    return size * (66.0 / 52.0)
        case .box:     return size * (58.0 / 52.0)  // give it a bit of horizontal padding to match the crab
        case .sparkle: return size
        }
    }

    // MARK: - Crab (Claude)

    private func drawCrab(context: GraphicsContext, canvasSize: CGSize) {
        let scale = size / 52.0
        let xOffset = (canvasSize.width - 66 * scale) / 2
        let t = CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: xOffset / scale, y: 0)

        func fill(_ rect: CGRect, _ color: Color) {
            context.fill(Path(rect).applying(t), with: .color(color))
        }

        fill(CGRect(x: 0,  y: 13, width: 6,  height: 13), palette.body) // left antenna
        fill(CGRect(x: 60, y: 13, width: 6,  height: 13), palette.body) // right antenna

        let legPositions: [CGFloat] = [6, 18, 42, 54]
        let legOffsets: [[CGFloat]] = [[3, -3, 3, -3], [0, 0, 0, 0], [-3, 3, -3, 3], [0, 0, 0, 0]]
        let active = animate ? legOffsets[animPhase % 4] : [CGFloat](repeating: 0, count: 4)
        for (i, x) in legPositions.enumerated() {
            fill(CGRect(x: x, y: 39, width: 6, height: 13 + active[i]), palette.body)
        }

        fill(CGRect(x: 6,  y: 0,  width: 54, height: 39),  palette.body) // body
        fill(CGRect(x: 12, y: 13, width: 6,  height: 6.5), palette.eyes) // left eye
        fill(CGRect(x: 48, y: 13, width: 6,  height: 6.5), palette.eyes) // right eye
    }

    // MARK: - Box (Codex)
    // Chunky cube — head bump, wide body, ">" eye + "_" mouth, two stubby feet.
    // Logical space is 58×52 so it visually matches the crab's footprint.
    private func drawBox(context: GraphicsContext, canvasSize: CGSize) {
        let scale = size / 52.0
        let xOffset = (canvasSize.width - 58 * scale) / 2
        let t = CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: xOffset / scale, y: 0)

        func fill(_ rect: CGRect, _ color: Color) {
            context.fill(Path(rect).applying(t), with: .color(color))
        }

        // Head bump (centered)
        fill(CGRect(x: 23, y: 0, width: 12, height: 7), palette.body)

        // Shoulders — narrower top of the body
        fill(CGRect(x: 6, y: 7, width: 46, height: 7), palette.body)

        // Wide main body — taller so the silhouette fills the canvas like the crab does
        fill(CGRect(x: 0, y: 14, width: 58, height: 28), palette.body)

        // Terminal-prompt face: ">" on the left, "_" on the right.
        // ">" — three 5×5 blocks forming a chevron
        fill(CGRect(x:  9, y: 19, width: 5, height: 5), palette.eyes)
        fill(CGRect(x: 14, y: 24, width: 5, height: 5), palette.eyes)
        fill(CGRect(x:  9, y: 29, width: 5, height: 5), palette.eyes)
        // "_" — horizontal bar
        fill(CGRect(x: 32, y: 31, width: 15, height: 4), palette.eyes)

        // Two stubby feet — walking animation bobs them up/down
        let baseY: CGFloat = 42
        let footHeight: CGFloat = 10
        let footOffsets: [[CGFloat]] = [[2, -2], [0, 0], [-2, 2], [0, 0]]
        let off = animate ? footOffsets[animPhase % 4] : [0, 0]
        fill(CGRect(x: 14, y: baseY, width: 10, height: footHeight + off[0]), palette.body)
        fill(CGRect(x: 34, y: baseY, width: 10, height: footHeight + off[1]), palette.body)
    }

    // MARK: - Sparkle (Gemini placeholder — 4-pointed star)

    private func drawSparkle(context: GraphicsContext, canvasSize: CGSize) {
        let scale = size / 52.0
        let xOffset = (canvasSize.width - 52 * scale) / 2
        let t = CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: xOffset / scale, y: 0)
        func fill(_ rect: CGRect, _ color: Color) {
            context.fill(Path(rect).applying(t), with: .color(color))
        }
        // Vertical bar + horizontal bar = 4-pointed star
        fill(CGRect(x: 22, y: 0, width: 8, height: 52), palette.body)
        fill(CGRect(x: 0, y: 22, width: 52, height: 8), palette.body)
        // Center diamond
        fill(CGRect(x: 18, y: 18, width: 16, height: 16), palette.body)
    }
}

/// Animated mascot that picks shape, palette, and animation based on session
/// status + provider. Transient statuses (thinking/error/waiting) override
/// the provider palette so the user can read the status at a glance.
struct SessionMascot: View {
    let status: SessionStatus
    var size: CGFloat = 16
    var animated: Bool = true
    var provider: AIProvider = .claude

    var body: some View {
        PixelMascot(
            size: size,
            palette: paletteFor(status),
            shape: provider.mascotShape,
            animate: animated && isActive
        )
    }

    private var isActive: Bool {
        status == .thinking || status == .toolUse
    }

    private func paletteFor(_ status: SessionStatus) -> PixelMascot.MascotPalette {
        switch status {
        case .thinking, .toolUse: return provider.activeMascotPalette
        case .idle, .completed:   return provider.mascotPalette
        case .error:              return .error
        case .waitingPermission:  return .waiting
        }
    }
}
