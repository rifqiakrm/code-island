import SwiftUI

/// A notch-attached shape: flat on top, rounded only on bottom corners.
/// Seamlessly extends from the hardware notch.
struct NotchShape: Shape {
    var cornerRadius: CGFloat

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = cornerRadius

        // Start top-left (flat edge)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Top edge — completely flat
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Right edge down to bottom-right corner
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        // Bottom-right rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        // Bottom edge
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        // Bottom-left rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        // Left edge back to top
        path.closeSubpath()

        return path
    }
}

/// The notch background. The Default theme fills pure black to blend with the
/// hardware notch (no stroke — it reads as an unwanted border on Tahoe's
/// compositor). Other themes supply their own fill + a flush-top border.
struct NotchBackground: View {
    var theme: NotchTheme = .defaultTheme
    let isExpanded: Bool
    let cornerRadius: CGFloat
    /// When false, only the fill is drawn (the parent draws the border on top of
    /// its content instead, so scrolling cards can't cover the window edge).
    /// Defaults true for standalone uses (onboarding faux notch, theme previews).
    var drawBorder: Bool = true
    /// How the theme's creature (if any) sets its lenses — driven by aggregate
    /// session state. Ignored by themes without a `windowCreature`.
    var creatureLens: SpiderLens = .wide
    /// Whether the creature's idle animation ticks. False keeps it perfectly
    /// still, which is what an idle notch should cost.
    var creatureAnimates: Bool = false

    @State private var webProgress: CGFloat = 0

    var body: some View {
        if isExpanded {
            // Only the expanded windows wear the theme. The collapsed strip
            // must stay pure black with no border so it blends seamlessly into
            // the hardware notch — a tinted fill or edge reads as a pasted-on
            // widget and breaks the illusion.
            if drawBorder {
                themedFill.overlay(border)
            } else {
                themedFill
            }
        } else {
            NotchShape(cornerRadius: cornerRadius)
                .fill(.black)
        }
    }

    /// The window fill plus any backdrop decoration. Everything here sits behind
    /// the panel's content — the web and the spider read through the translucent
    /// cards rather than competing with them for space.
    @ViewBuilder
    private var themedFill: some View {
        fill
            .overlay {
                if case .web(let thread, let alpha) = theme.windowPattern {
                    WebOverlay(thread: thread, alpha: alpha, progress: webProgress)
                        .onAppear {
                            // Spins itself in once, then never redraws again.
                            withAnimation(.easeOut(duration: 0.55)) { webProgress = 1 }
                        }
                }
            }
            .overlay(alignment: .topTrailing) {
                if case .spider(let inset) = theme.windowCreature {
                    WebSlingerSpider(lens: creatureLens, animate: creatureAnimates)
                        .padding(.trailing, inset)
                }
            }
            .clipShape(NotchShape(cornerRadius: cornerRadius))
    }

    /// The window edge border, exposed so a parent can render it on top of its
    /// own content (z-order fix for thick Pixel/Brutalist borders).
    @ViewBuilder
    var borderOverlay: some View { border }

    @ViewBuilder
    private var fill: some View {
        switch theme.windowFill {
        case .solid(let color):
            NotchShape(cornerRadius: cornerRadius)
                .fill(color)
        case .material(let material, let tint):
            NotchShape(cornerRadius: cornerRadius)
                .fill(material)
                .overlay(
                    NotchShape(cornerRadius: cornerRadius)
                        .fill(tint)
                )
        }
    }

    @ViewBuilder
    private var border: some View {
        if let stroke = theme.windowStroke {
            // Drawn at the path edge and clipped to the shape by the parent, so
            // doubling the width renders a crisp inside border of the intended
            // thickness. NotchBorderShape omits the top edge to stay flush.
            NotchBorderShape(cornerRadius: cornerRadius)
                .stroke(stroke, lineWidth: theme.windowStrokeWidth * 2)
        }
    }
}
