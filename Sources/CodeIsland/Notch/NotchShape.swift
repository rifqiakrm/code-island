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

    var body: some View {
        if isExpanded {
            // Only the expanded windows wear the theme. The collapsed strip
            // must stay pure black with no border so it blends seamlessly into
            // the hardware notch — a tinted fill or edge reads as a pasted-on
            // widget and breaks the illusion.
            if drawBorder {
                fill.overlay(border)
            } else {
                fill
            }
        } else {
            NotchShape(cornerRadius: cornerRadius)
                .fill(.black)
        }
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
