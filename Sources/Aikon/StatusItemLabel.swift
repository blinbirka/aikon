import SwiftUI
import AppKit

struct Counts: Equatable {
    var waiting = 0   // needs permission + needs answer
    var done = 0
    var busy = 0
}

/// The three pairs shown in the menu bar, and — through `image(counts:)` —
/// in the menu bar itself.
///
/// It has to become a picture to get there. A `MenuBarExtra` label accepts
/// text, an image, or text with an image, and nothing more: a composed view
/// is reduced, symbols concatenated into a `Text` are dropped (that version
/// showed the numbers and none of the glyphs), and colour is thrown away
/// because the system renders the label as a template, tinted to match the
/// bar. Drawing the whole row into one non-template image is the way past
/// all three at once, and it is `App.swift` that hands the result to
/// `MenuBarExtra` — `ImageRenderer` cannot run inside the label closure.
struct StatusItemLabel: View {
    let counts: Counts

    /// Spacing inside a pair, and between pairs. Her pick out of three
    /// mock-ups: the tightest, because the menu bar is shared space.
    private let insidePair: CGFloat = 2
    private let betweenPairs: CGFloat = 10

    var body: some View {
        HStack(spacing: betweenPairs) {
            pair(.needsPermission, counts.waiting)
            pair(.finished, counts.done)
            pair(.working, counts.busy)
        }
        .font(.system(size: 13))
        .monospacedDigit()
    }

    private func pair(_ status: SessionStatus, _ count: Int) -> some View {
        HStack(spacing: insidePair) {
            glyph(status)
                // The working dot is a solid disc where the other two are
                // detailed shapes; at a shared size it reads twice as heavy.
                .font(.system(size: status == .working ? 8 : 12))
                .frame(width: 14)
            Text("\(count)")
                .foregroundStyle(status.symbolColor)
        }
    }

    /// Palette rendering for the two symbols that have an inner mark: in the
    /// `.fill` variants the tick and the exclamation are holes punched through
    /// the shape, so the menu bar — and whatever wallpaper shows through it —
    /// came up inside them. Filling them black is what the emoji used to do.
    ///
    /// The working dot has no second layer, and palette's first colour would
    /// simply paint the whole disc black, so it stays monochrome.
    @ViewBuilder
    private func glyph(_ status: SessionStatus) -> some View {
        if status == .working {
            Image(systemName: status.symbolName)
                .foregroundStyle(status.symbolColor)
        } else {
            Image(systemName: status.symbolName)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.black, status.symbolColor)
        }
    }
}

extension StatusItemLabel {
    /// The row as an image, ready for `MenuBarExtra`'s label.
    ///
    /// `isTemplate = false` keeps the colours, and the cost is that nothing
    /// recolours the label for the bar underneath it. macOS darkens the menu
    /// bar over a dark desktop picture even while the system appearance is
    /// light, and tells no one: `NSApp.effectiveAppearance` still says light.
    /// So no neutral colour is safe here, and the label carries none — every
    /// glyph and every number is drawn in its status's own colour, which
    /// stands on a bar of either shade.
    @MainActor
    static func image(counts: Counts, appearance: NSAppearance?) -> NSImage? {
        var image: NSImage?
        let render = {
            let renderer = ImageRenderer(content: StatusItemLabel(counts: counts))
            renderer.scale = 2   // one point is two pixels on every Mac made since 2012
            if let cgImage = renderer.cgImage {
                let size = NSSize(width: CGFloat(cgImage.width) / 2,
                                  height: CGFloat(cgImage.height) / 2)
                let made = NSImage(cgImage: cgImage, size: size)
                made.isTemplate = false
                image = made
            }
        }
        if let appearance {
            appearance.performAsCurrentDrawingAppearance(render)
        } else {
            render()
        }
        return image
    }
}
