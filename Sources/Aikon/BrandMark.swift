import SwiftUI

/// The approved mark: a diamond (a square rotated 45°), drawn with `Path`
/// rather than a text glyph like `"♦"` or `"A"` — a font glyph shifts across
/// systems and weights, a shape doesn't.
struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

/// The app's logo: an accent-filled rounded square with a diamond centered
/// on it. Used at two sizes — the settings sidebar (28pt, see `Sidebar` in
/// `SettingsView`) and the About section's hero (56pt) — so both stay in
/// sync with a single definition instead of two hand-copied views.
struct BrandMark: View {
    var size: CGFloat
    var cornerRadius: CGFloat
    var markSize: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.accent)
            .frame(width: size, height: size)
            .overlay(
                // White, not `Theme.textOnAccent`: that token goes dark in dark
                // mode, and the mark then read as a hole punched in the accent
                // square. The app icon and the menu bar strip in the README
                // always drew it white — this brings the rest in line.
                DiamondShape()
                    .fill(.white)
                    .frame(width: markSize, height: markSize)
            )
    }
}
