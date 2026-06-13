import SwiftUI

// MARK: - Theme identity

/// The user-selectable visual languages for the notch windows.
///
/// Themes restyle **chrome only** — window background, card/box/pill/button
/// shape language, borders, shadows, and font design. They deliberately do
/// NOT touch semantic or brand colors: provider accents (Claude terracotta,
/// Codex gray), mascot palettes, status colors (cyan thinking / green idle /
/// orange waiting / red error), tool colors, action-button red/green/purple,
/// and rate-limit thresholds all stay constant so the crab is always the crab
/// and red always means deny.
enum NotchThemeID: String, CaseIterable, Identifiable {
    case `default`
    case glass
    case pixel
    case terminal
    case brutalist

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default:   return "Default"
        case .glass:     return "Liquid Glass"
        case .pixel:     return "Retro Pixel"
        case .terminal:  return "Terminal"
        case .brutalist: return "Brutalist"
        }
    }

    var blurb: String {
        switch self {
        case .default:   return "The original — pure black, monospaced, soft rounded cards."
        case .glass:     return "Frosted translucency, pill controls, native macOS feel."
        case .pixel:     return "8-bit chunky borders, square corners, hard offset shadows."
        case .terminal:  return "Pure black, hairline dividers, near-invisible chrome."
        case .brutalist: return "Thick borders, bold sans type, flat heavy fills."
        }
    }

    var theme: NotchTheme { NotchTheme.all[self] ?? .defaultTheme }
}

// MARK: - Shadow & window-fill value types

struct NotchShadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

enum NotchWindowFill {
    case solid(Color)
    /// A blur material plus a tint overlay to keep text legible.
    case material(Material, tint: Color)
}

/// How a theme treats pill corners. Pills are authored with a "base" radius
/// (status pills 5, mini-badges 4, filter chips 6, option pills 20); the theme
/// decides whether to honour that, square it, capsule it, or cap it. `.asAuthored`
/// keeps the Default theme pixel-faithful.
enum PillCorner {
    case asAuthored
    case square
    case capsule
    case cap(CGFloat)

    func radius(base: CGFloat) -> CGFloat {
        switch self {
        case .asAuthored: return base
        case .square:     return 0
        case .capsule:    return max(base, 999)
        case .cap(let m): return min(base, m)
        }
    }
}

// MARK: - The token set

/// A pure token set consumed by every notch view. No view logic here — just
/// values. Views read it via `@Environment(\.notchTheme)`.
struct NotchTheme {
    let id: NotchThemeID

    // Window chrome (drawn by NotchBackground)
    let windowFill: NotchWindowFill
    /// Inside border traced on the sides + bottom only (flush top preserves the
    /// seamless-notch illusion). `nil` = no border.
    let windowStroke: Color?
    let windowStrokeWidth: CGFloat

    // Corner radii for each surface class
    let cardRadius: CGFloat
    let boxRadius: CGFloat
    /// Pills resolve their radius from a per-call base via this policy.
    let pillCorner: PillCorner
    let buttonRadius: CGFloat

    // Border thickness applied to themed surfaces
    let strokeWidth: CGFloat

    // Drop shadow applied to cards / boxes / buttons (`nil` = none)
    let surfaceShadow: NotchShadow?

    // Neutral (non-tinted) surface colors
    let neutralCardFill: Color
    let neutralCardStroke: Color
    let boxFill: Color
    let boxStroke: Color

    // Tinted-card opacities — status cards keep their semantic tint colour but
    // borrow these opacities so each theme controls how loud the tint reads.
    let cardTintFillActive: Double
    let cardTintFillIdle: Double
    let cardTintStrokeActive: Double
    let cardTintStrokeIdle: Double

    // Typography
    let fontDesign: Font.Design

    // --- Extended chrome. Declared with defaults so the three themes that
    //     don't need them stay untouched. ---

    /// Cards render as light surfaces with dark text (Brutalist). Drives chip
    /// inversion and the on-card inset well treatment.
    var lightCards: Bool = false
    /// Primary text colour for card body content; flips dark on light-card themes.
    var cardForeground: Color = .white
    /// Text colour for content inside inset wells (command/diff preview, reply,
    /// input). Flips dark on themes with light/cream wells (Brutalist).
    var wellForeground: Color = .white
    /// Wells/boxes are light surfaces (Brutalist cream) → use the light syntax
    /// palette so code stays legible on them.
    var lightWells: Bool = false
    /// Hard offset shadows borrow the surface's tint colour (Pixel) so they stay
    /// visible on the dark window instead of an invisible near-black.
    var tintedShadow: Bool = false
    /// Forces a fixed card border colour regardless of tint (Brutalist = black).
    var cardStrokeOverride: Color? = nil

    /// Fixed activity hues (Pixel/Brutalist mockups): thinking cards go warm
    /// terracotta, idle cards go cool. `nil` = keep the per-status colour.
    /// Error/waiting always keep their semantic red/orange (set in the view).
    var cardHueActive: Color? = nil
    var cardHueIdle: Color? = nil

    /// Theme-aware font. Replaces `.system(size:weight:design:.monospaced)`
    /// call sites so a theme can swap the whole app between mono and sans.
    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: fontDesign)
    }

    /// Pills/badges sitting on a (possibly light) card. On light-card themes they
    /// become dark chips so their coloured text stays legible.
    func chipFill(_ base: Color) -> Color {
        lightCards ? Color.black.opacity(0.82) : base
    }

    /// Per-theme treatment for an action button given its semantic accent colour.
    /// Default/Glass/Terminal: tinted-glass fill, coloured text, no border.
    /// Pixel: dark fill + coloured border + coloured text (border carries the hue).
    /// Brutalist: SOLID accent fill + black border + dark text (loud, flat).
    func buttonInk(_ accent: Color) -> (fill: Color, stroke: Color?, text: Color) {
        switch id {
        case .brutalist:
            return (accent, .black, Color(red: 0.10, green: 0.10, blue: 0.11))
        case .pixel:
            return (accent.opacity(0.12), accent, accent)
        default:
            return (accent.opacity(0.08), nil, accent.opacity(0.95))
        }
    }
}

// MARK: - Theme instances

extension NotchTheme {
    static let all: [NotchThemeID: NotchTheme] = [
        .default:   .defaultTheme,
        .glass:     .glassTheme,
        .pixel:     .pixelTheme,
        .terminal:  .terminalTheme,
        .brutalist: .brutalistTheme,
    ]

    /// Exact reproduction of the shipped v1.1.6 look. Changing nothing here is
    /// load-bearing: existing users must see no difference on "Default".
    static let defaultTheme = NotchTheme(
        id: .default,
        windowFill: .solid(.black),
        windowStroke: nil,
        windowStrokeWidth: 0,
        cardRadius: 12,
        boxRadius: 8,
        pillCorner: .asAuthored,
        buttonRadius: 8,
        strokeWidth: 1,
        surfaceShadow: nil,
        neutralCardFill: .white.opacity(0.05),
        neutralCardStroke: .white.opacity(0.08),
        boxFill: .white.opacity(0.05),
        boxStroke: .white.opacity(0.08),
        cardTintFillActive: 0.05,
        cardTintFillIdle: 0.03,
        cardTintStrokeActive: 0.35,
        cardTintStrokeIdle: 0.15,
        fontDesign: .monospaced
    )

    static let glassTheme = NotchTheme(
        id: .glass,
        windowFill: .material(.ultraThinMaterial, tint: .black.opacity(0.34)),
        windowStroke: .white.opacity(0.18),
        windowStrokeWidth: 1,
        cardRadius: 16,
        boxRadius: 12,
        pillCorner: .capsule,
        buttonRadius: 99,
        strokeWidth: 1,
        surfaceShadow: NotchShadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 4),
        neutralCardFill: .white.opacity(0.10),
        neutralCardStroke: .white.opacity(0.18),
        boxFill: .black.opacity(0.28),
        boxStroke: .white.opacity(0.12),
        cardTintFillActive: 0.14,
        cardTintFillIdle: 0.08,
        cardTintStrokeActive: 0.45,
        cardTintStrokeIdle: 0.28,
        fontDesign: .default
    )

    static let pixelTheme = NotchTheme(
        id: .pixel,
        windowFill: .solid(Color(red: 0.059, green: 0.059, blue: 0.102)), // #0F0F1A
        windowStroke: .white.opacity(0.85),
        windowStrokeWidth: 2,
        cardRadius: 0,
        boxRadius: 0,
        pillCorner: .square,
        buttonRadius: 0,
        strokeWidth: 2,
        surfaceShadow: NotchShadow(color: .black.opacity(0.55), radius: 0, x: 3, y: 3),
        neutralCardFill: Color(red: 0.086, green: 0.086, blue: 0.122), // #16161F
        neutralCardStroke: .white.opacity(0.8),
        boxFill: .black,
        boxStroke: .white.opacity(0.85),
        cardTintFillActive: 0.12,
        cardTintFillIdle: 0.07,
        cardTintStrokeActive: 0.9,
        cardTintStrokeIdle: 0.6,
        fontDesign: .monospaced,
        tintedShadow: true,
        // Mockup hues: terracotta border when active, neutral gray when idle.
        cardHueActive: Color(red: 0.88, green: 0.47, blue: 0.34),
        cardHueIdle: Color(red: 0.55, green: 0.55, blue: 0.60)
    )

    static let terminalTheme = NotchTheme(
        id: .terminal,
        windowFill: .solid(.black),
        windowStroke: .white.opacity(0.10),
        windowStrokeWidth: 1,
        cardRadius: 6,
        boxRadius: 6,
        pillCorner: .cap(4),
        buttonRadius: 4,
        strokeWidth: 1,
        surfaceShadow: nil,
        neutralCardFill: .white.opacity(0.02),
        neutralCardStroke: .white.opacity(0.06),
        boxFill: .white.opacity(0.02),
        boxStroke: .white.opacity(0.08),
        cardTintFillActive: 0.04,
        cardTintFillIdle: 0.0,
        cardTintStrokeActive: 0.4,
        cardTintStrokeIdle: 0.18,
        fontDesign: .monospaced
    )

    static let brutalistTheme = NotchTheme(
        id: .brutalist,
        windowFill: .solid(Color(red: 0.071, green: 0.071, blue: 0.090)), // #121217
        windowStroke: .white.opacity(0.9),
        windowStrokeWidth: 3,
        cardRadius: 6,
        boxRadius: 6,
        pillCorner: .cap(6),
        buttonRadius: 6,
        strokeWidth: 3,
        surfaceShadow: NotchShadow(color: .white.opacity(0.9), radius: 0, x: 4, y: 4),
        neutralCardFill: .white.opacity(0.06),
        neutralCardStroke: .white.opacity(0.9),
        // Cream wells with a black border + dark text/syntax (mockup look).
        boxFill: Color(red: 0.96, green: 0.95, blue: 0.91),
        boxStroke: .black,
        // Cards are vivid LIGHT surfaces — the tint shows at high opacity with
        // dark text + a black border + a hard white offset shadow.
        cardTintFillActive: 0.92,
        cardTintFillIdle: 0.80,
        cardTintStrokeActive: 0.95,
        cardTintStrokeIdle: 0.7,
        fontDesign: .default,
        lightCards: true,
        cardForeground: Color(red: 0.10, green: 0.10, blue: 0.11),
        wellForeground: Color(red: 0.12, green: 0.12, blue: 0.13),
        lightWells: true,
        cardStrokeOverride: .black,
        // Mockup hues: vivid terracotta card when active, sky-blue when idle.
        cardHueActive: Color(red: 0.88, green: 0.47, blue: 0.34),
        cardHueIdle: Color(red: 0.49, green: 0.83, blue: 0.99)
    )
}

// MARK: - Environment plumbing

private struct NotchThemeKey: EnvironmentKey {
    static let defaultValue: NotchTheme = .defaultTheme
}

extension EnvironmentValues {
    var notchTheme: NotchTheme {
        get { self[NotchThemeKey.self] }
        set { self[NotchThemeKey.self] = newValue }
    }
}

// MARK: - Flush-top border shape

/// Like `NotchShape` but draws an OPEN path with no top edge, so stroking it
/// leaves the top flush with the hardware notch (no seam line) while bordering
/// the visible left / bottom / right edges.
struct NotchBorderShape: Shape {
    var cornerRadius: CGFloat

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = cornerRadius
        // Start at top-right, trace down the right edge, around the bottom, up
        // the left edge — but never close across the top.
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        return path
    }
}

// MARK: - Themed surface modifiers

private struct SurfaceShadow: ViewModifier {
    let shadow: NotchShadow?
    func body(content: Content) -> some View {
        if let s = shadow {
            content.shadow(color: s.color, radius: s.radius, x: s.x, y: s.y)
        } else {
            content
        }
    }
}

/// The shadow actually drawn for a surface: a theme with `tintedShadow` recolours
/// its hard offset to the surface's tint so it stays visible on the dark window.
private func resolvedShadow(_ theme: NotchTheme, tint: Color?) -> NotchShadow? {
    guard let s = theme.surfaceShadow else { return nil }
    if theme.tintedShadow, let t = tint {
        return NotchShadow(color: t.opacity(0.55), radius: s.radius, x: s.x, y: s.y)
    }
    return s
}

extension View {
    /// Drop-in replacement for the card background. When `tint` is given (the
    /// semantic status colour of a session card) the fill/border borrow the
    /// theme's tint opacities; otherwise the neutral card surface is used.
    func notchCard(_ theme: NotchTheme, tint: Color? = nil, active: Bool = false) -> some View {
        let fill: Color = tint.map { $0.opacity(active ? theme.cardTintFillActive : theme.cardTintFillIdle) }
            ?? theme.neutralCardFill
        let stroke: Color = theme.cardStrokeOverride
            ?? tint.map { $0.opacity(active ? theme.cardTintStrokeActive : theme.cardTintStrokeIdle) }
            ?? theme.neutralCardStroke
        return self
            .background(
                // Fill + shadow sit BEHIND the content. (Shadow on the shape, not
                // `self` — otherwise SwiftUI ghosts every glyph inside the card.)
                RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
                    .fill(fill)
                    .modifier(SurfaceShadow(shadow: resolvedShadow(theme, tint: tint)))
            )
            .overlay(
                // Border sits ON TOP of the content so pills/text never break the
                // edge line (most visible with the thick Brutalist border).
                RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: theme.strokeWidth)
            )
    }

    /// Neutral inset box / well (command preview, conversation sub-box, etc.).
    func notchBox(_ theme: NotchTheme) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: theme.boxRadius, style: .continuous)
                    .fill(theme.boxFill)
                    .modifier(SurfaceShadow(shadow: theme.surfaceShadow))
            )
            .overlay(
                RoundedRectangle(cornerRadius: theme.boxRadius, style: .continuous)
                    .strokeBorder(theme.boxStroke, lineWidth: theme.strokeWidth)
            )
    }

    /// Small status / option pill. Colours are passed explicitly because they
    /// are usually semantic; the theme only controls radius + border weight.
    /// `base` is the pill's authored radius (status 5, badges 4, option pills
    /// 20) — the theme's `pillCorner` policy decides what to do with it.
    func notchPill(_ theme: NotchTheme, fill: Color, stroke: Color? = nil, base: CGFloat = 5) -> some View {
        let r = theme.pillCorner.radius(base: base)
        return self
            .background(
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: r, style: .continuous)
                            .strokeBorder(stroke ?? .clear, lineWidth: stroke == nil ? 0 : theme.strokeWidth)
                    )
            )
    }

    /// Action button surface. Carries the theme's surface shadow so pixel /
    /// brutalist buttons get their hard offset.
    func notchButton(_ theme: NotchTheme, fill: Color, stroke: Color? = nil) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: theme.buttonRadius, style: .continuous)
                    .fill(fill)
                    // Tint the hard shadow to the button's own colour (Pixel) so
                    // it reads on the dark window; Brutalist keeps its white offset.
                    .modifier(SurfaceShadow(shadow: resolvedShadow(theme, tint: stroke ?? fill)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: theme.buttonRadius, style: .continuous)
                    .strokeBorder(stroke ?? .clear, lineWidth: stroke == nil ? 0 : theme.strokeWidth)
            )
    }
}
