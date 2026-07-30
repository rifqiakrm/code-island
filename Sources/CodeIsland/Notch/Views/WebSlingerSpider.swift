import SwiftUI
import Combine

// MARK: - Lens state

/// How the mask's lenses are set. This is a *status readout*, not decoration —
/// the aggregate session state maps onto the squint so the notch stays readable
/// even when the cards themselves are too small to parse.
enum SpiderLens: Equatable {
    case wide       // idle / nothing running — relaxed, full-height lenses
    case narrow     // thinking or using a tool — squinted to a band
    case alarmed    // a permission/question is waiting — blown wide
    case symbiote   // a session errored — mask goes black, lenses slit + jagged
}

// MARK: - Corner webbing

/// The web spun into the two top corners of an expanded notch window.
///
/// Seven spokes fan across each corner quadrant; five rings sag between adjacent
/// spokes as quadratic curves pulled back toward the anchor. Rings fade outward
/// so the web never competes with a session card sitting on top of it.
///
/// `progress` drives the one-shot spin-in (spokes first, then rings outward).
/// At rest it sits at 1 and the Canvas never redraws — the notch is a
/// transparent overlay, so anything that ticks forever costs real CPU.
struct WebOverlay: View {
    var thread: Color
    var alpha: Double
    var progress: CGFloat
    /// How far the web extends from each corner. Sized so the two corner webs
    /// meet across the middle of a 600pt panel — the sweeping arcs are the look,
    /// a tighter web reads as a small motif stuck in the corner. Scale it down
    /// proportionally for previews.
    var reach: CGFloat = 340

    private let spokes = 7
    private let rings = 5
    private let sag: CGFloat = 0.14

    var body: some View {
        Canvas { ctx, size in
            draw(ctx, anchor: CGPoint(x: 0, y: 0), from: 8, to: 82)
            draw(ctx, anchor: CGPoint(x: size.width, y: 0), from: 172, to: 98)
        }
        .allowsHitTesting(false)
    }

    private func point(_ anchor: CGPoint, _ a0: CGFloat, _ a1: CGFloat,
                       _ i: Int, _ ring: Int) -> CGPoint {
        let t = CGFloat(i) / CGFloat(spokes - 1)
        let a = (a0 + (a1 - a0) * t) * .pi / 180
        let r = reach * CGFloat(ring) / CGFloat(rings)
        return CGPoint(x: anchor.x + cos(a) * r, y: anchor.y + sin(a) * r)
    }

    private func draw(_ ctx: GraphicsContext, anchor: CGPoint, from a0: CGFloat, to a1: CGFloat) {
        // Spokes occupy the first 40% of the spin-in, rings the rest.
        let spokeP = min(1, progress / 0.4)
        var radials = Path()
        for i in 0..<spokes {
            let p = point(anchor, a0, a1, i, rings)
            radials.move(to: anchor)
            radials.addLine(to: CGPoint(x: anchor.x + (p.x - anchor.x) * spokeP,
                                        y: anchor.y + (p.y - anchor.y) * spokeP))
        }
        ctx.stroke(radials, with: .color(thread.opacity(alpha * 0.83)), lineWidth: 1)

        guard progress > 0.4 else { return }
        let ringP = (progress - 0.4) / 0.6
        for k in 1...rings {
            guard CGFloat(k - 1) / CGFloat(rings) <= ringP else { break }
            var arc = Path()
            for j in 0..<(spokes - 1) {
                let a = point(anchor, a0, a1, j, k)
                let b = point(anchor, a0, a1, j + 1, k)
                let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                arc.move(to: a)
                arc.addQuadCurve(
                    to: b,
                    control: CGPoint(x: mid.x + (anchor.x - mid.x) * sag,
                                     y: mid.y + (anchor.y - mid.y) * sag)
                )
            }
            // Fade outward: the innermost ring reads, the outermost barely does.
            let fade = alpha - Double(k - 1) * (alpha * 0.18)
            ctx.stroke(arc, with: .color(thread.opacity(max(0, fade))), lineWidth: 1)
        }
    }
}

// MARK: - The masked spider

/// A pixel-art spider whose body *is* the mask — red dome, black web seam, two
/// white lenses. Authored the same way as every mascot in `PixelMascot`: hard
/// rects on a logical grid, no anti-aliasing, no vector curves.
///
/// It runs on the crab's own cadence (`Timer.publish(every: 0.15)`, 4 phases):
/// legs twitch by parity, the body bobs, and the thread lengthens to match so it
/// dangles instead of sliding. The timer only advances when `animate` is true,
/// so an idle notch is completely still.
struct WebSlingerSpider: View {
    var lens: SpiderLens = .wide
    var animate: Bool = false
    /// Points per logical pixel-art unit.
    var unit: CGFloat = 1.5

    @State private var animPhase: Int = 0
    @State private var descended = false
    private let animTimer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    // Sprite geometry, in logical units.
    private static let spriteW = 24
    private static let spriteH = 24
    private static let bodyX = 5
    private static let bodyW = 14
    private static let bodyH = 12
    /// Where the sprite's top edge comes to rest after the abseil.
    private static let settled: CGFloat = 9

    /// The mask. `R` = suit, `k` = black web seam, `.` = empty. Lenses are
    /// punched over the top afterwards so one body serves every lens state.
    private static let mask = [
        "...RRRRRRRR...",
        "..RRRkRRkRRR..",
        ".RRRRRkkRRRRR.",
        ".RRRRRkkRRRRR.",
        ".RRRRRkkRRRRR.",
        ".RRRRRkkRRRRR.",
        ".RRRRRkkRRRRR.",
        ".RRRkRkkRkRRR.",
        "..RRRRkkRRRR..",
        "..RRRRkkRRRR..",
        "...RRRRRRRR...",
        "....RRRRRR....",
    ]

    /// Four legs down the left side, as pixel runs in sprite space; the right
    /// side mirrors them. The last pixel of each run is the tip that twitches.
    ///
    /// Every step moves along one axis only, so consecutive pixels share an
    /// *edge*. Pure diagonals touch at corners and read as dotted specks at this
    /// scale rather than as limbs.
    ///
    /// Short and squared off on purpose — at 1.5pt per unit these read as a
    /// tucked-in, clinging posture, which suits a spider hanging still on a
    /// thread better than long splayed limbs would.
    private static let legs: [[(Int, Int)]] = [
        [(4, 2), (3, 2), (3, 1), (2, 1), (2, 0), (1, 0)],     // up and out
        [(4, 4), (3, 4), (2, 4), (1, 4), (1, 3)],
        [(4, 7), (3, 7), (2, 7), (1, 7), (1, 8)],
        [(4, 9), (3, 9), (3, 10), (2, 10), (2, 11), (1, 11)], // down and out
    ]

    private struct LensShape {
        let rows: ClosedRange<Int>
        let x: Int
        let width: Int
        let jagged: Bool
    }

    private var lensShape: LensShape {
        switch lens {
        case .wide:     return LensShape(rows: 3...6, x: 1, width: 4, jagged: false)
        case .narrow:   return LensShape(rows: 4...5, x: 2, width: 3, jagged: false)
        case .alarmed:  return LensShape(rows: 2...6, x: 1, width: 5, jagged: false)
        case .symbiote: return LensShape(rows: 5...5, x: 1, width: 4, jagged: true)
        }
    }

    private var skin: (mask: Color, legs: Color, seam: Color, lens: Color) {
        switch lens {
        case .symbiote:
            return (Color(red: 0.102, green: 0.106, blue: 0.133),
                    Color(red: 0.063, green: 0.067, blue: 0.086),
                    .black,
                    Color(red: 0.910, green: 0.925, blue: 0.961))
        case .narrow:
            return (Color(red: 1.000, green: 0.231, blue: 0.255),
                    Color(red: 0.769, green: 0.129, blue: 0.157),
                    Color(red: 0.039, green: 0.047, blue: 0.086),
                    .white)
        default:
            return (Color(red: 0.902, green: 0.141, blue: 0.161),
                    Color(red: 0.690, green: 0.106, blue: 0.125),
                    Color(red: 0.039, green: 0.047, blue: 0.086),
                    Color(red: 0.957, green: 0.969, blue: 1.000))
        }
    }

    var body: some View {
        Canvas { ctx, _ in draw(ctx) }
            .frame(width: CGFloat(Self.spriteW) * unit,
                   height: CGFloat(Self.spriteH) * unit)
            .allowsHitTesting(false)
            // The abseil rides on `.offset`, NOT on a value read inside the
            // Canvas closure. A Canvas only redraws when something invalidates
            // the view, and the only thing that does here is the leg timer —
            // which is gated on `animate`. Driving the descent from inside the
            // closure left the spider stuck at its first frame (fully offscreen,
            // i.e. invisible) any time no session was running. `.offset` is
            // genuinely animatable, and its worst case is the spider simply
            // appearing at rest rather than vanishing.
            .offset(y: descended ? 0 : -CGFloat(Self.spriteH) * unit)
            .onAppear {
                withAnimation(.easeOut(duration: 0.45)) { descended = true }
            }
            .onReceive(animTimer) { _ in
                if animate { animPhase = (animPhase + 1) % 4 }
            }
    }

    private func draw(_ ctx: GraphicsContext) {
        let ink = skin
        // The crab's bob, at pixel-grid resolution.
        let bob: CGFloat = animate ? [0, -1, -2, -1][animPhase % 4] : 0
        // Always drawn at rest; the descent is the parent `.offset`. Whole units
        // only, so the pixel art never lands off-grid.
        let top = Self.settled + bob

        func px(_ x: Int, _ y: CGFloat, _ color: Color) {
            guard y >= 0 else { return }
            ctx.fill(
                Path(CGRect(x: CGFloat(x) * unit, y: y * unit, width: unit, height: unit)),
                with: .color(color)
            )
        }

        // Thread — anchored to the window's top edge, stretching with the bob.
        if top > 0 {
            let tx = CGFloat(Self.bodyX + Self.bodyW / 2) * unit
            ctx.fill(Path(CGRect(x: tx, y: 0, width: unit, height: top * unit)),
                     with: .color(Color(red: 0.788, green: 0.824, blue: 0.910).opacity(0.45)))
        }

        // Legs — tips lift by parity, the same trick as the crab's leg-walk.
        for side in 0..<2 {
            for (i, run) in Self.legs.enumerated() {
                let lift: CGFloat = (i % 2 == animPhase % 2) ? -1 : 1
                for (j, p) in run.enumerated() {
                    let x = side == 0 ? p.0 : Self.spriteW - 1 - p.0
                    let y = CGFloat(p.1) + (j == run.count - 1 && animate ? lift : 0)
                    px(x, y + top, ink.legs)
                }
            }
        }

        // Mask body
        for (r, row) in Self.mask.enumerated() {
            for (c, ch) in row.enumerated() where ch != "." {
                px(Self.bodyX + c, CGFloat(r) + top, ch == "k" ? ink.seam : ink.mask)
            }
        }

        // Lenses, punched over the mask on both sides
        let shape = lensShape
        for ly in shape.rows {
            for w in 0..<shape.width {
                // The symbiote's lenses lose their outer pixel on alternate rows
                // so the slit reads torn rather than tidy.
                if shape.jagged && w == shape.width - 1 && ly % 2 == 0 { continue }
                px(Self.bodyX + shape.x + w, CGFloat(ly) + top, ink.lens)
                px(Self.bodyX + Self.bodyW - 1 - shape.x - w, CGFloat(ly) + top, ink.lens)
            }
        }
    }
}
