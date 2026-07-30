import SwiftUI
import Combine

/// Pixel-art mascot view. The drawing routine is chosen by `shape` — each
/// provider gets its own silhouette (crab for Claude, box for Codex, ...).
struct PixelMascot: View {
    var size: CGFloat = 16
    var palette: MascotPalette = .claude
    var shape: MascotShape = .crab
    var animate: Bool = false
    /// Pulls the Web-Slinger mask over the mascot. Honoured only by `.crab` and
    /// `.box` — they're the two shapes with a readable face to cover; every
    /// other mascot ignores it.
    var masked: Bool = false

    @State private var animPhase: Int = 0
    private let animTimer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    enum MascotShape {
        case crab        // Claude — antennae + 4 walking legs + body + 2 eyes
        case box         // Codex — chunky cube with head bump + 1 eye + 2 stubby feet
        case sparkle     // (legacy Gemini placeholder — kept for back-compat)
        case geminiStar  // Gemini — blue→purple plus/star creature
        case qwenGem     // Qwen — faceted violet gem head + chevron eyes
        case qoderBlob   // Qoder — round green smiley blob
        case factoryBot  // Factory/Droid — boxy orange industrial robot
        case buddyCat    // CodeBuddy — purple cat astronaut
        case cursorBox   // Cursor — dark monitor box w/ corner notch
        case copilotBot  // Copilot — goggled rose robot
        case kimiMoon    // Kimi — dark navy orb with a glowing crescent + eyes
        case openCodeMark // OpenCode — dark terminal box w/ "-O-" face + feet
        case clineBot    // Cline — rounded green bot, head knob, side ears, tall eyes
        case kiroGhost   // Kiro — violet friendly ghost w/ wavy tail
        case piGlyph     // Pi / Oh My Pi — π-shaped two-legged creature
        case antigravityOrbit // AntiGravity — blue planet floating in an orbit ring
        case hermesWing  // Hermes — gold winged messenger helmet
    }

    enum MascotPalette {
        // Idle / branded
        case claude, codex, gemini
        case qwen, qoder, factory, codebuddy, cursor, copilot
        case kimi, opencode, cline
        case kiro, pi, omp, antigravity, hermes
        // Brand-tinted "active" palettes (thinking / using a tool)
        case claudeActive, codexActive, geminiActive
        case qwenActive, qoderActive, factoryActive, codebuddyActive, cursorActive, copilotActive
        case kimiActive, opencodeActive, clineActive
        case kiroActive, piActive, ompActive
        case antigravityActive, hermesActive
        // Universal semantic palettes
        case error
        case waiting

        var body: Color {
            switch self {
            case .claude:           return Color(red: 0.85, green: 0.47, blue: 0.34)
            case .codex:            return Color(red: 0.92, green: 0.92, blue: 0.92)
            case .gemini:           return Color(red: 0.278, green: 0.588, blue: 0.894)
            case .qwen:             return Color(red: 0.486, green: 0.228, blue: 0.929)
            case .qoder:            return Color(red: 0.165, green: 0.859, blue: 0.361)
            case .factory:          return Color(red: 0.835, green: 0.416, blue: 0.149)
            case .codebuddy:        return Color(red: 0.424, green: 0.302, blue: 1.000)
            case .cursor:           return Color(red: 0.130, green: 0.120, blue: 0.090)
            case .copilot:          return Color(red: 0.800, green: 0.200, blue: 0.400)
            case .claudeActive:     return Color(red: 0.30, green: 0.75, blue: 0.90)  // cyan
            case .codexActive:      return Color(red: 0.60, green: 0.85, blue: 1.00)  // bright sky blue
            case .geminiActive:     return Color(red: 0.518, green: 0.478, blue: 0.808)
            case .qwenActive:       return Color(red: 0.659, green: 0.510, blue: 0.984)
            case .qoderActive:      return Color(red: 0.40, green: 1.00, blue: 0.58)
            case .factoryActive:    return Color(red: 0.945, green: 0.565, blue: 0.235)
            case .codebuddyActive:  return Color(red: 0.196, green: 0.902, blue: 0.725)
            case .cursorActive:     return Color(red: 0.30, green: 0.28, blue: 0.24)
            case .copilotActive:    return Color(red: 0.93, green: 0.38, blue: 0.56)
            case .kimi:             return Color(red: 0.29, green: 0.56, blue: 1.00)  // Kimi blue #4A90FF
            case .kimiActive:       return Color(red: 0.46, green: 0.72, blue: 1.00)  // brighter lunar glow
            case .opencode:         return Color(red: 0.220, green: 0.220, blue: 0.240)  // #383838 dark gray
            case .opencodeActive:   return Color(red: 0.345, green: 0.345, blue: 0.365)  // lighter when active
            case .cline:            return Color(red: 0.00, green: 0.70, blue: 0.49)  // Cline green #00B37D
            case .clineActive:      return Color(red: 0.20, green: 0.90, blue: 0.66)  // brighter green
            case .kiro:             return Color(red: 0.49, green: 0.36, blue: 1.00)
            case .kiroActive:       return Color(red: 0.64, green: 0.54, blue: 1.00)
            case .pi:               return Color(red: 0.96, green: 0.69, blue: 0.13)
            case .piActive:         return Color(red: 1.00, green: 0.82, blue: 0.36)
            case .omp:              return Color(red: 0.13, green: 0.78, blue: 0.74)
            case .ompActive:        return Color(red: 0.34, green: 0.92, blue: 0.88)
            case .antigravity:      return Color(red: 0.259, green: 0.522, blue: 0.957)
            case .antigravityActive: return Color(red: 0.451, green: 0.667, blue: 1.000)
            case .hermes:           return Color(red: 0.953, green: 0.722, blue: 0.196)
            case .hermesActive:     return Color(red: 1.000, green: 0.831, blue: 0.353)
            case .error:            return Color(red: 0.90, green: 0.35, blue: 0.30)
            case .waiting:          return Color(red: 1.00, green: 0.72, blue: 0.30)
            }
        }

        var eyes: Color { .black }
    }

    var body: some View {
        Canvas { context, canvasSize in
            switch shape {
            case .crab:
                drawCrab(context: context, canvasSize: canvasSize)
                if masked { drawCrabMask(context: context, canvasSize: canvasSize) }
            case .box:
                drawBox(context: context, canvasSize: canvasSize)
                if masked { drawBoxMask(context: context, canvasSize: canvasSize) }
            case .sparkle:     drawSparkle(context: context, canvasSize: canvasSize)
            case .geminiStar:  drawShape(context, canvasSize, 44, drawGeminiStar)
            case .qwenGem:     drawShape(context, canvasSize, 54, drawQwenGem)
            case .qoderBlob:   drawShape(context, canvasSize, 52, drawQoderBlob)
            case .factoryBot:  drawShape(context, canvasSize, 58, drawFactoryBot)
            case .buddyCat:    drawShape(context, canvasSize, 60, drawBuddyCat)
            case .cursorBox:   drawShape(context, canvasSize, 52, drawCursorBox)
            case .copilotBot:  drawShape(context, canvasSize, 52, drawCopilotBot)
            case .kimiMoon:    drawShape(context, canvasSize, 52, drawKimiMoon)
            case .openCodeMark: drawShape(context, canvasSize, 50, drawOpenCodeMark)
            case .clineBot:    drawShape(context, canvasSize, 48, drawClineBot)
            case .kiroGhost:   drawShape(context, canvasSize, 48, drawKiroGhost)
            case .piGlyph:     drawShape(context, canvasSize, 48, drawPiGlyph)
            case .antigravityOrbit: drawShape(context, canvasSize, 52, drawAntigravityOrbit)
            case .hermesWing:  drawShape(context, canvasSize, 58, drawHermesWing)
            }
        }
        .frame(width: aspectAdjustedWidth, height: size)
        .onReceive(animTimer) { _ in
            if animate { animPhase = (animPhase + 1) % 4 }
        }
    }

    private var aspectAdjustedWidth: CGFloat {
        switch shape {
        case .crab:        return size * (66.0 / 52.0)
        case .box:         return size * (58.0 / 52.0)  // give it a bit of horizontal padding to match the crab
        case .sparkle:     return size
        case .geminiStar:  return size * (44.0 / 52.0)
        case .qwenGem:     return size * (54.0 / 52.0)
        case .qoderBlob:   return size
        case .factoryBot:  return size * (58.0 / 52.0)
        case .buddyCat:    return size * (60.0 / 52.0)
        case .cursorBox:   return size
        case .copilotBot:  return size
        case .kimiMoon:    return size                  // 52/52
        case .openCodeMark: return size * (50.0 / 52.0)
        case .clineBot:    return size * (48.0 / 52.0)
        case .kiroGhost:   return size * (48.0 / 52.0)
        case .piGlyph:     return size * (48.0 / 52.0)
        case .antigravityOrbit: return size
        case .hermesWing:  return size * (58.0 / 52.0)
        }
    }

    /// Shared helper for the provider mascots: sets up the 52-tall logical
    /// transform + a `fill` closure and hands them to a per-shape draw block.
    private func drawShape(_ context: GraphicsContext, _ canvasSize: CGSize, _ logicalWidth: CGFloat,
                           _ draw: (GraphicsContext, (CGRect, Color) -> Void) -> Void) {
        let scale = size / 52.0
        let xOffset = (canvasSize.width - logicalWidth * scale) / 2
        // Thinking bounce: gently bob the whole body up/down (gives the provider
        // mascots the same "alive" feel as the crab's leg-walk / box's foot-bob,
        // without a per-mascot leg rig).
        let bob: CGFloat = animate ? [0, -1.5, -3, -1.5][animPhase % 4] : 0
        let t = CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: xOffset / scale, y: bob)
        func fill(_ rect: CGRect, _ color: Color) {
            context.fill(Path(rect).applying(t), with: .color(color))
        }
        draw(context, fill)
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

    // MARK: - Web-Slinger mask

    // The one sanctioned exception to "themes never touch mascots". Drawn on top
    // of the finished mascot, so it covers the eyes the shape already painted.
    // Only the crab and the box wear one: masking a mascot whose face isn't a
    // pair of eyes (Gemini's star, Kiro's ghost) reads as a smudge, not a mask.

    private static let maskRed  = Color(red: 0.902, green: 0.141, blue: 0.161)
    private static let maskSeam = Color(red: 0.039, green: 0.047, blue: 0.086)
    private static let maskLens = Color(red: 0.957, green: 0.969, blue: 1.000)

    /// Crab: a hood pulled down over the eyes, leaving the lower shell showing
    /// so the status palette still reads underneath.
    private func drawCrabMask(context: GraphicsContext, canvasSize: CGSize) {
        let scale = size / 52.0
        let xOffset = (canvasSize.width - 66 * scale) / 2
        let t = CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: xOffset / scale, y: 0)
        func fill(_ rect: CGRect, _ color: Color) {
            context.fill(Path(rect).applying(t), with: .color(color))
        }
        // The antennae go under the hood too — left bare they read as blue ears
        // stuck on the side of a red mask.
        fill(CGRect(x: 0,  y: 13, width: 6, height: 13), Self.maskRed)
        fill(CGRect(x: 60, y: 13, width: 6, height: 13), Self.maskRed)
        // Hood across the shell (body spans x 6…60), hemmed with a dark edge.
        fill(CGRect(x: 6, y: 0,  width: 54, height: 22), Self.maskRed)
        fill(CGRect(x: 6, y: 22, width: 54, height: 2),  Self.maskSeam)
        // Centre web seam, splitting the lenses.
        fill(CGRect(x: 32, y: 0, width: 2, height: 22), Self.maskSeam)
        // Lenses over where the crab's eyes were (x 12…18 / 48…54). The dark
        // rect underneath is the outline — a bare white block reads as a robot
        // eye, and the heavy black border is what makes it Spider-Man's lens.
        fill(CGRect(x: 9,  y: 8, width: 15, height: 12), Self.maskSeam)
        fill(CGRect(x: 42, y: 8, width: 15, height: 12), Self.maskSeam)
        fill(CGRect(x: 10, y: 9, width: 13, height: 10), Self.maskLens)
        fill(CGRect(x: 43, y: 9, width: 13, height: 10), Self.maskLens)
    }

    /// Box: same treatment, hemmed high enough that the terminal-prompt face
    /// still peeks out below like a mouth under the mask.
    private func drawBoxMask(context: GraphicsContext, canvasSize: CGSize) {
        let scale = size / 52.0
        let xOffset = (canvasSize.width - 58 * scale) / 2
        let t = CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: xOffset / scale, y: 0)
        func fill(_ rect: CGRect, _ color: Color) {
            context.fill(Path(rect).applying(t), with: .color(color))
        }
        // Follows the box's own silhouette: head bump, shoulders, upper body.
        fill(CGRect(x: 23, y: 0,  width: 12, height: 7),  Self.maskRed)
        fill(CGRect(x: 6,  y: 7,  width: 46, height: 7),  Self.maskRed)
        fill(CGRect(x: 0,  y: 14, width: 58, height: 16), Self.maskRed)
        fill(CGRect(x: 0,  y: 30, width: 58, height: 2),  Self.maskSeam)
        fill(CGRect(x: 28, y: 0,  width: 2,  height: 30), Self.maskSeam)
        // Outlined lenses, same reasoning as the crab's.
        fill(CGRect(x: 5,  y: 15, width: 20, height: 12), Self.maskSeam)
        fill(CGRect(x: 33, y: 15, width: 20, height: 12), Self.maskSeam)
        fill(CGRect(x: 6,  y: 16, width: 18, height: 10), Self.maskLens)
        fill(CGRect(x: 34, y: 16, width: 18, height: 10), Self.maskLens)
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

    // MARK: - Provider mascots (ported from reference gifs / brand-designed)

    private func drawGeminiStar(_ context: GraphicsContext, _ fill: (CGRect, Color) -> Void) {
        let blue = palette.body
        let purple = Color(red: 0.518, green: 0.478, blue: 0.808)
        let foot = Color(red: 0.36, green: 0.33, blue: 0.55)
        let eye = Color.white
        fill(CGRect(x: 14, y: 0, width: 16, height: 14), blue)
        fill(CGRect(x: 0,  y: 14, width: 22, height: 16), blue)
        fill(CGRect(x: 22, y: 14, width: 22, height: 16), purple)
        fill(CGRect(x: 13, y: 17, width: 7, height: 8), eye)
        fill(CGRect(x: 24, y: 17, width: 7, height: 8), eye)
        fill(CGRect(x: 12, y: 30, width: 20, height: 12), purple)
        fill(CGRect(x: 13, y: 42, width: 7, height: 9), foot)
        fill(CGRect(x: 24, y: 42, width: 7, height: 9), foot)
    }

    private func drawQwenGem(_ context: GraphicsContext, _ fill: (CGRect, Color) -> Void) {
        let accentHi = Color(red: 0.659, green: 0.510, blue: 0.984)
        let accentDk = Color(red: 0.427, green: 0.157, blue: 0.851)
        let gemEye   = Color(red: 0.78, green: 0.92, blue: 1.0)
        fill(CGRect(x: 19, y: 2,  width: 16, height: 5),  palette.body)
        fill(CGRect(x: 12, y: 7,  width: 30, height: 5),  palette.body)
        fill(CGRect(x: 6,  y: 12, width: 42, height: 7),  palette.body)
        fill(CGRect(x: 3,  y: 19, width: 48, height: 8),  palette.body)
        fill(CGRect(x: 6,  y: 27, width: 42, height: 6),  palette.body)
        fill(CGRect(x: 12, y: 33, width: 30, height: 5),  palette.body)
        fill(CGRect(x: 19, y: 38, width: 16, height: 4),  palette.body)
        fill(CGRect(x: 22, y: 8,  width: 10, height: 4),  accentHi)
        fill(CGRect(x: 16, y: 12, width: 22, height: 4),  accentHi)
        fill(CGRect(x: 12, y: 16, width: 9,  height: 4),  accentHi)
        fill(CGRect(x: 34, y: 22, width: 12, height: 9),  accentDk)
        fill(CGRect(x: 30, y: 31, width: 10, height: 4),  accentDk)
        fill(CGRect(x: 13, y: 19, width: 4, height: 4),  gemEye)
        fill(CGRect(x: 17, y: 22, width: 4, height: 4),  gemEye)
        fill(CGRect(x: 13, y: 25, width: 4, height: 4),  gemEye)
        fill(CGRect(x: 30, y: 19, width: 4, height: 4),  gemEye)
        fill(CGRect(x: 34, y: 22, width: 4, height: 4),  gemEye)
        fill(CGRect(x: 30, y: 25, width: 4, height: 4),  gemEye)
        fill(CGRect(x: 18, y: 42, width: 7, height: 9),  accentDk)
        fill(CGRect(x: 29, y: 42, width: 7, height: 9),  accentDk)
    }

    private func drawQoderBlob(_ context: GraphicsContext, _ fill: (CGRect, Color) -> Void) {
        fill(CGRect(x: 18, y: 2,  width: 16, height: 4), palette.body)
        fill(CGRect(x: 12, y: 6,  width: 28, height: 4), palette.body)
        fill(CGRect(x: 8,  y: 10, width: 36, height: 4), palette.body)
        fill(CGRect(x: 4,  y: 14, width: 44, height: 22), palette.body)
        fill(CGRect(x: 8,  y: 36, width: 36, height: 4), palette.body)
        fill(CGRect(x: 12, y: 40, width: 28, height: 3), palette.body)
        fill(CGRect(x: 16, y: 18, width: 6, height: 7), palette.eyes)
        fill(CGRect(x: 30, y: 18, width: 6, height: 7), palette.eyes)
        fill(CGRect(x: 16, y: 28, width: 4, height: 3), palette.eyes)
        fill(CGRect(x: 20, y: 30, width: 4, height: 3), palette.eyes)
        fill(CGRect(x: 24, y: 31, width: 4, height: 3), palette.eyes)
        fill(CGRect(x: 28, y: 30, width: 4, height: 3), palette.eyes)
        fill(CGRect(x: 32, y: 28, width: 4, height: 3), palette.eyes)
        fill(CGRect(x: 14, y: 43, width: 7, height: 7), palette.body)
        fill(CGRect(x: 31, y: 43, width: 7, height: 7), palette.body)
    }

    private func drawFactoryBot(_ context: GraphicsContext, _ fill: (CGRect, Color) -> Void) {
        let bodyDark = Color(red: 0.62, green: 0.30, blue: 0.11)
        let metal    = Color(red: 0.40, green: 0.37, blue: 0.34)
        let metalLt  = Color(red: 0.52, green: 0.49, blue: 0.46)
        let gold     = Color(red: 0.89, green: 0.60, blue: 0.16)
        fill(CGRect(x: 27, y: 0,  width: 4,  height: 6), metal)
        fill(CGRect(x: 24, y: 0,  width: 10, height: 4), gold)
        fill(CGRect(x: 0,  y: 22, width: 7,  height: 18), metal)
        fill(CGRect(x: 51, y: 22, width: 7,  height: 18), metal)
        fill(CGRect(x: 0,  y: 22, width: 7,  height: 3),  metalLt)
        fill(CGRect(x: 51, y: 22, width: 7,  height: 3),  metalLt)
        fill(CGRect(x: 7,  y: 6,  width: 44, height: 38), palette.body)
        fill(CGRect(x: 12, y: 13, width: 34, height: 11), bodyDark)
        fill(CGRect(x: 17, y: 16, width: 9,  height: 5),  gold)
        fill(CGRect(x: 32, y: 16, width: 9,  height: 5),  gold)
        fill(CGRect(x: 20, y: 17, width: 3,  height: 3),  palette.eyes)
        fill(CGRect(x: 35, y: 17, width: 3,  height: 3),  palette.eyes)
        fill(CGRect(x: 16, y: 27, width: 26, height: 13), bodyDark)
        fill(CGRect(x: 18, y: 29, width: 3,  height: 3),  metal)
        fill(CGRect(x: 37, y: 29, width: 3,  height: 3),  metal)
        fill(CGRect(x: 18, y: 35, width: 3,  height: 3),  metal)
        fill(CGRect(x: 37, y: 35, width: 3,  height: 3),  metal)
        fill(CGRect(x: 14, y: 44, width: 12, height: 8),  metal)
        fill(CGRect(x: 32, y: 44, width: 12, height: 8),  metal)
        fill(CGRect(x: 14, y: 44, width: 12, height: 2),  metalLt)
        fill(CGRect(x: 32, y: 44, width: 12, height: 2),  metalLt)
    }

    private func drawBuddyCat(_ context: GraphicsContext, _ fill: (CGRect, Color) -> Void) {
        let cyan = Color(red: 0.196, green: 0.902, blue: 0.725)
        let darkBand = Color(red: 0.165, green: 0.129, blue: 0.314)
        let bodyDk = Color(red: 0.345, green: 0.243, blue: 0.827)
        fill(CGRect(x: 6,  y: 0,  width: 11, height: 6),  palette.body)
        fill(CGRect(x: 43, y: 0,  width: 11, height: 6),  palette.body)
        fill(CGRect(x: 8,  y: 0,  width: 7,  height: 3),  cyan)
        fill(CGRect(x: 45, y: 0,  width: 7,  height: 3),  cyan)
        fill(CGRect(x: 4,  y: 6,  width: 52, height: 11), palette.body)
        fill(CGRect(x: 8,  y: 17, width: 44, height: 11), darkBand)
        fill(CGRect(x: 17, y: 20, width: 8,  height: 6),  cyan)
        fill(CGRect(x: 35, y: 20, width: 8,  height: 6),  cyan)
        fill(CGRect(x: 4,  y: 28, width: 52, height: 12), palette.body)
        fill(CGRect(x: 56, y: 30, width: 4,  height: 8),  palette.body)
        fill(CGRect(x: 14, y: 40, width: 11, height: 12), bodyDk)
        fill(CGRect(x: 35, y: 40, width: 11, height: 12), bodyDk)
    }

    private func drawCursorBox(_ context: GraphicsContext, _ fill: (CGRect, Color) -> Void) {
        let eyeC = palette.eyes
        let pale = Color(red: 0.93, green: 0.93, blue: 0.93)
        let notchC = Color(red: 0.42, green: 0.40, blue: 0.36)
        fill(CGRect(x: 4, y: 6, width: 44, height: 34), palette.body)
        fill(CGRect(x: 34, y: 0, width: 14, height: 9), notchC)
        fill(CGRect(x: 34, y: 6, width: 14, height: 3), palette.body)
        fill(CGRect(x: 11, y: 17, width: 9, height: 9), pale)
        fill(CGRect(x: 14, y: 20, width: 3, height: 3), eyeC)
        fill(CGRect(x: 26, y: 18, width: 14, height: 2), pale)
        fill(CGRect(x: 26, y: 24, width: 11, height: 2), pale)
        fill(CGRect(x: 26, y: 30, width: 13, height: 2), pale)
        fill(CGRect(x: 12, y: 40, width: 8, height: 9), palette.body)
        fill(CGRect(x: 32, y: 40, width: 8, height: 9), palette.body)
    }

    private func drawCopilotBot(_ context: GraphicsContext, _ fill: (CGRect, Color) -> Void) {
        let gold = Color(red: 1.00, green: 0.84, blue: 0.00)
        let visor = Color(red: 0.13, green: 0.13, blue: 0.16)
        let ear = Color(red: 0.20, green: 0.20, blue: 0.20)
        fill(CGRect(x: 24, y: 0, width: 4, height: 6), ear)
        fill(CGRect(x: 21, y: 0, width: 10, height: 3), gold)
        fill(CGRect(x: 4, y: 7, width: 12, height: 4), ear)
        fill(CGRect(x: 4, y: 11, width: 4, height: 4), ear)
        fill(CGRect(x: 12, y: 11, width: 4, height: 4), ear)
        fill(CGRect(x: 36, y: 7, width: 12, height: 4), ear)
        fill(CGRect(x: 36, y: 11, width: 4, height: 4), ear)
        fill(CGRect(x: 44, y: 11, width: 4, height: 4), ear)
        fill(CGRect(x: 10, y: 13, width: 32, height: 4), palette.body)
        fill(CGRect(x: 6, y: 17, width: 40, height: 26), palette.body)
        fill(CGRect(x: 10, y: 43, width: 32, height: 4), palette.body)
        fill(CGRect(x: 11, y: 21, width: 30, height: 16), visor)
        fill(CGRect(x: 14, y: 23, width: 11, height: 11), gold)
        fill(CGRect(x: 16, y: 25, width: 7, height: 7), visor)
        fill(CGRect(x: 18, y: 27, width: 4, height: 4), gold)
        fill(CGRect(x: 27, y: 23, width: 11, height: 11), gold)
        fill(CGRect(x: 29, y: 25, width: 7, height: 7), visor)
        fill(CGRect(x: 31, y: 27, width: 4, height: 4), gold)
        fill(CGRect(x: 25, y: 27, width: 2, height: 3), gold)
        fill(CGRect(x: 20, y: 39, width: 12, height: 2), palette.body)
        fill(CGRect(x: 14, y: 47, width: 8, height: 5), palette.body)
        fill(CGRect(x: 30, y: 47, width: 8, height: 5), palette.body)
    }

    // MARK: - Kimi (lunar orb + glowing crescent)

    private func drawKimiMoon(_ context: GraphicsContext, _ fill: (CGRect, Color) -> Void) {
        let navy     = Color(red: 0.10, green: 0.13, blue: 0.26)   // deep lunar-night body
        let navyEdge = Color(red: 0.16, green: 0.20, blue: 0.36)   // lighter rim highlight
        let crescent = palette.body                                // brand blue / active glow
        let glowHi   = Color(red: 0.78, green: 0.88, blue: 1.00)   // bright inner crescent edge
        let eye      = palette.eyes                                // black
        let spark    = Color(red: 0.95, green: 0.96, blue: 1.00)   // little star

        // Round-ish orb body (stacked bars)
        fill(CGRect(x: 19, y: 3,  width: 14, height: 4),  navy)
        fill(CGRect(x: 13, y: 7,  width: 26, height: 4),  navy)
        fill(CGRect(x: 8,  y: 11, width: 36, height: 5),  navy)
        fill(CGRect(x: 5,  y: 16, width: 42, height: 20), navy)
        fill(CGRect(x: 8,  y: 36, width: 36, height: 5),  navy)
        fill(CGRect(x: 13, y: 41, width: 26, height: 4),  navy)
        fill(CGRect(x: 19, y: 45, width: 14, height: 4),  navy)

        // Rim highlight along the upper-left edge
        fill(CGRect(x: 13, y: 7,  width: 26, height: 2),  navyEdge)
        fill(CGRect(x: 8,  y: 11, width: 5,  height: 5),  navyEdge)
        fill(CGRect(x: 5,  y: 16, width: 3,  height: 12), navyEdge)

        // Glowing crescent (right side)
        fill(CGRect(x: 34, y: 11, width: 5,  height: 5),  crescent)
        fill(CGRect(x: 38, y: 15, width: 6,  height: 6),  crescent)
        fill(CGRect(x: 40, y: 21, width: 6,  height: 10), crescent)
        fill(CGRect(x: 38, y: 31, width: 6,  height: 6),  crescent)
        fill(CGRect(x: 34, y: 36, width: 5,  height: 5),  crescent)
        fill(CGRect(x: 33, y: 16, width: 3,  height: 4),  glowHi)
        fill(CGRect(x: 35, y: 22, width: 3,  height: 8),  glowHi)
        fill(CGRect(x: 33, y: 32, width: 3,  height: 4),  glowHi)

        // Face: two eyes + glints
        fill(CGRect(x: 17, y: 22, width: 5,  height: 7),  eye)
        fill(CGRect(x: 26, y: 22, width: 5,  height: 7),  eye)
        fill(CGRect(x: 18, y: 23, width: 2,  height: 2),  glowHi)
        fill(CGRect(x: 27, y: 23, width: 2,  height: 2),  glowHi)

        // Little twinkle star, upper-right
        fill(CGRect(x: 44, y: 5,  width: 2,  height: 6),  spark)
        fill(CGRect(x: 42, y: 7,  width: 6,  height: 2),  spark)
    }

    // MARK: - OpenCode (terminal monitor box, "-O-" face)

    private func drawOpenCodeMark(_ context: GraphicsContext, _ fill: (CGRect, Color) -> Void) {
        let frame = Color(red: 0.55, green: 0.55, blue: 0.57)  // light-gray bezel
        let face  = Color(red: 0.85, green: 0.85, blue: 0.87)  // light face wells
        let foot  = Color(red: 0.35, green: 0.35, blue: 0.37)  // darker legs

        // Light frame/bezel (body insets to leave a 2px edge)
        fill(CGRect(x: 1,  y: 4,  width: 48, height: 34), frame)
        // Dark monitor body
        fill(CGRect(x: 3,  y: 6,  width: 44, height: 30), palette.body)
        // Top bezel highlight strip
        fill(CGRect(x: 3,  y: 6,  width: 44, height: 3),  frame)

        // "-O-" terminal face
        fill(CGRect(x: 12, y: 16, width: 5,  height: 11), face)  // left bar eye
        fill(CGRect(x: 22, y: 18, width: 6,  height: 6),  face)  // center "O"
        fill(CGRect(x: 33, y: 16, width: 5,  height: 11), face)  // right bar eye
        fill(CGRect(x: 13, y: 19, width: 3,  height: 5),  palette.eyes)
        fill(CGRect(x: 34, y: 19, width: 3,  height: 5),  palette.eyes)

        // Two stubby feet
        fill(CGRect(x: 11, y: 38, width: 8,  height: 8),  foot)
        fill(CGRect(x: 31, y: 38, width: 8,  height: 8),  foot)
    }

    // MARK: - Cline (rounded green bot)

    private func drawClineBot(_ context: GraphicsContext, _ fill: (CGRect, Color) -> Void) {
        let body  = palette.body
        let dark  = Color(red: 0.00, green: 0.42, blue: 0.30) // shaded green underbelly
        let light = Color(red: 0.30, green: 0.92, blue: 0.70) // top highlight knob
        let eye   = Color.white

        // Head knob (centered)
        fill(CGRect(x: 20, y: 0,  width: 8,  height: 6),  light)
        fill(CGRect(x: 18, y: 4,  width: 12, height: 4),  body)

        // Side "ears" flanking the body
        fill(CGRect(x: 0,  y: 20, width: 6,  height: 16), body)
        fill(CGRect(x: 42, y: 20, width: 6,  height: 16), body)

        // Rounded body silhouette (stacked bars)
        fill(CGRect(x: 10, y: 8,  width: 28, height: 4),  body) // shoulders
        fill(CGRect(x: 6,  y: 12, width: 36, height: 28), body) // main mass
        fill(CGRect(x: 10, y: 40, width: 28, height: 4),  body) // chin

        // Shaded underbelly band
        fill(CGRect(x: 8,  y: 36, width: 32, height: 5),  dark)

        // Two tall white eyes
        fill(CGRect(x: 16, y: 18, width: 6,  height: 14), eye)
        fill(CGRect(x: 26, y: 18, width: 6,  height: 14), eye)

        // Two short legs/feet
        fill(CGRect(x: 14, y: 44, width: 8,  height: 7),  dark)
        fill(CGRect(x: 26, y: 44, width: 8,  height: 7),  dark)
    }

    // MARK: - Kiro (ghost)
    private func drawKiroGhost(_ context: GraphicsContext, _ fill: (CGRect, Color) -> Void) {
        let body = palette.body
        let eyeW = Color.white
        fill(CGRect(x: 14, y: 2,  width: 20, height: 5),  body)
        fill(CGRect(x: 9,  y: 7,  width: 30, height: 6),  body)
        fill(CGRect(x: 6,  y: 13, width: 36, height: 24), body)
        fill(CGRect(x: 13, y: 18, width: 9,  height: 11), eyeW)
        fill(CGRect(x: 26, y: 18, width: 9,  height: 11), eyeW)
        fill(CGRect(x: 16, y: 22, width: 4,  height: 5),  palette.eyes)
        fill(CGRect(x: 29, y: 22, width: 4,  height: 5),  palette.eyes)
        fill(CGRect(x: 6,  y: 37, width: 9,  height: 8),  body)
        fill(CGRect(x: 19, y: 37, width: 10, height: 8),  body)
        fill(CGRect(x: 33, y: 37, width: 9,  height: 8),  body)
        fill(CGRect(x: 6,  y: 45, width: 9,  height: 4),  body)
        fill(CGRect(x: 19, y: 45, width: 10, height: 4),  body)
        fill(CGRect(x: 33, y: 45, width: 9,  height: 4),  body)
    }

    // MARK: - Pi / Oh My Pi (π creature)
    private func drawPiGlyph(_ context: GraphicsContext, _ fill: (CGRect, Color) -> Void) {
        let body = palette.body
        let eyeW = Color.white
        fill(CGRect(x: 4,  y: 8,  width: 40, height: 12), body)
        fill(CGRect(x: 8,  y: 4,  width: 32, height: 4),  body)
        fill(CGRect(x: 13, y: 10, width: 7,  height: 8),  eyeW)
        fill(CGRect(x: 28, y: 10, width: 7,  height: 8),  eyeW)
        fill(CGRect(x: 16, y: 12, width: 3,  height: 4),  palette.eyes)
        fill(CGRect(x: 31, y: 12, width: 3,  height: 4),  palette.eyes)
        fill(CGRect(x: 12, y: 20, width: 9,  height: 24), body)
        fill(CGRect(x: 28, y: 20, width: 9,  height: 24), body)
        fill(CGRect(x: 37, y: 38, width: 6,  height: 6),  body)
        fill(CGRect(x: 10, y: 44, width: 11, height: 6),  body)
        fill(CGRect(x: 28, y: 44, width: 11, height: 6),  body)
    }

    // MARK: - AntiGravity (floating planet + orbit)
    private func drawAntigravityOrbit(_ context: GraphicsContext, _ fill: (CGRect, Color) -> Void) {
        let body = palette.body
        let edge = Color(red: 0.55, green: 0.74, blue: 1.00)
        let ring = Color(red: 0.78, green: 0.82, blue: 0.90)
        let ringDk = Color(red: 0.50, green: 0.54, blue: 0.64)
        let face = Color(red: 0.92, green: 0.96, blue: 1.00)
        let spark = Color(red: 1.00, green: 0.96, blue: 0.70)
        fill(CGRect(x: 4,  y: 16, width: 6,  height: 4),  ringDk)
        fill(CGRect(x: 42, y: 16, width: 6,  height: 4),  ringDk)
        fill(CGRect(x: 10, y: 13, width: 32, height: 4),  ringDk)
        fill(CGRect(x: 18, y: 13, width: 16, height: 4),  body)
        fill(CGRect(x: 12, y: 17, width: 28, height: 5),  body)
        fill(CGRect(x: 9,  y: 22, width: 34, height: 12), body)
        fill(CGRect(x: 12, y: 34, width: 28, height: 5),  body)
        fill(CGRect(x: 18, y: 39, width: 16, height: 4),  body)
        fill(CGRect(x: 12, y: 17, width: 24, height: 2),  edge)
        fill(CGRect(x: 9,  y: 22, width: 3,  height: 8),  edge)
        fill(CGRect(x: 2,  y: 30, width: 8,  height: 4),  ring)
        fill(CGRect(x: 42, y: 30, width: 8,  height: 4),  ring)
        fill(CGRect(x: 6,  y: 33, width: 40, height: 4),  ring)
        fill(CGRect(x: 17, y: 23, width: 5,  height: 7),  face)
        fill(CGRect(x: 30, y: 23, width: 5,  height: 7),  face)
        fill(CGRect(x: 18, y: 24, width: 3,  height: 4),  palette.eyes)
        fill(CGRect(x: 31, y: 24, width: 3,  height: 4),  palette.eyes)
        fill(CGRect(x: 46, y: 4,  width: 2,  height: 6),  spark)
        fill(CGRect(x: 44, y: 6,  width: 6,  height: 2),  spark)
    }

    // MARK: - Hermes (winged helmet)
    private func drawHermesWing(_ context: GraphicsContext, _ fill: (CGRect, Color) -> Void) {
        let helm = palette.body
        let edge = Color(red: 1.00, green: 0.86, blue: 0.42)
        let dark = Color(red: 0.72, green: 0.50, blue: 0.10)
        let wing = Color(red: 0.96, green: 0.97, blue: 1.00)
        let wingDk = Color(red: 0.74, green: 0.80, blue: 0.90)
        let visor = Color(red: 0.20, green: 0.16, blue: 0.06)
        fill(CGRect(x: 0,  y: 14, width: 12, height: 4),  wing)
        fill(CGRect(x: 2,  y: 18, width: 12, height: 4),  wing)
        fill(CGRect(x: 5,  y: 22, width: 11, height: 4),  wing)
        fill(CGRect(x: 0,  y: 17, width: 12, height: 1),  wingDk)
        fill(CGRect(x: 2,  y: 21, width: 12, height: 1),  wingDk)
        fill(CGRect(x: 46, y: 14, width: 12, height: 4),  wing)
        fill(CGRect(x: 44, y: 18, width: 12, height: 4),  wing)
        fill(CGRect(x: 42, y: 22, width: 11, height: 4),  wing)
        fill(CGRect(x: 46, y: 17, width: 12, height: 1),  wingDk)
        fill(CGRect(x: 44, y: 21, width: 12, height: 1),  wingDk)
        fill(CGRect(x: 22, y: 2,  width: 14, height: 4),  helm)
        fill(CGRect(x: 18, y: 6,  width: 22, height: 5),  helm)
        fill(CGRect(x: 15, y: 11, width: 28, height: 16), helm)
        fill(CGRect(x: 22, y: 2,  width: 14, height: 2),  edge)
        fill(CGRect(x: 18, y: 6,  width: 4,  height: 5),  edge)
        fill(CGRect(x: 15, y: 27, width: 28, height: 4),  dark)
        fill(CGRect(x: 19, y: 16, width: 8,  height: 6),  visor)
        fill(CGRect(x: 31, y: 16, width: 8,  height: 6),  visor)
        fill(CGRect(x: 21, y: 18, width: 3,  height: 3),  edge)
        fill(CGRect(x: 33, y: 18, width: 3,  height: 3),  edge)
        fill(CGRect(x: 19, y: 31, width: 20, height: 9),  helm)
        fill(CGRect(x: 22, y: 40, width: 14, height: 4),  helm)
        fill(CGRect(x: 21, y: 44, width: 7,  height: 7),  dark)
        fill(CGRect(x: 30, y: 44, width: 7,  height: 7),  dark)
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

    @Environment(\.notchTheme) private var theme

    var body: some View {
        PixelMascot(
            size: size,
            palette: paletteFor(status),
            shape: provider.mascotShape,
            animate: animated && isActive,
            masked: theme.masksMascots
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
