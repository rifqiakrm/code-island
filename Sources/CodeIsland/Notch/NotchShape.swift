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

/// The notch background — pure black to blend with the hardware notch.
struct NotchBackground: View {
    let isExpanded: Bool
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            // Pure black to match the notch
            NotchShape(cornerRadius: cornerRadius)
                .fill(.black)

            // Subtle bottom/side border glow (not on top — that's the notch)
            NotchShape(cornerRadius: cornerRadius)
                .stroke(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.08), .white.opacity(0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        }
    }
}
