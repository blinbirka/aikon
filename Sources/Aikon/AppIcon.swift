import AppKit

/// A programmatically drawn Dock icon: the same rounded-square-plus-diamond
/// mark as `BrandMark`, rasterized with `NSBezierPath` since the Dock icon
/// needs an `NSImage`, not a SwiftUI view. There's no bundled `.icns` yet —
/// this only covers the brief window (see `SettingsWindowCoordinator`)
/// where Aikon switches to `.regular` and would otherwise show a blank
/// generic icon in the Dock while Settings is open.
enum AppIcon {
    /// 512×512, the standard largest raw size for an app icon; AppKit scales
    /// it down for the Dock and window title bar as needed.
    static let image: NSImage = draw(size: 512)

    private static func draw(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            // ~22% corner radius matches how macOS rounds its own app icons.
            let cornerRadius = rect.width * 0.22
            let background = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor(rgb: 0xFF8A4C).setFill()
            background.fill()

            // Same proportion as the 56pt About mark's 24pt diamond (24/56).
            let markSize = rect.width * (24.0 / 56.0)
            let markRect = CGRect(x: rect.midX - markSize / 2, y: rect.midY - markSize / 2,
                                   width: markSize, height: markSize)
            let diamond = NSBezierPath()
            diamond.move(to: CGPoint(x: markRect.midX, y: markRect.minY))
            diamond.line(to: CGPoint(x: markRect.maxX, y: markRect.midY))
            diamond.line(to: CGPoint(x: markRect.midX, y: markRect.maxY))
            diamond.line(to: CGPoint(x: markRect.minX, y: markRect.midY))
            diamond.close()
            NSColor.white.setFill()
            diamond.fill()

            return true
        }
    }
}
