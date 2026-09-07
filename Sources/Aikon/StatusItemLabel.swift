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
        // Not `.primary`: this view is rasterized, so the colour has to be
        // resolved against the menu bar's appearance at render time rather
        // than left for SwiftUI to adapt later — see `image(counts:)`.
        .foregroundStyle(Color(nsColor: .labelColor))
    }

    private func pair(_ status: SessionStatus, _ count: Int) -> some View {
        HStack(spacing: insidePair) {
            Image(systemName: status.symbolName)
                // The working dot is a solid disc where the other two are
                // detailed shapes; at a shared size it reads twice as heavy.
                .font(.system(size: status == .working ? 8 : 12))
                .foregroundStyle(status.symbolColor)
                .frame(width: 14)
            Text("\(count)")
        }
    }
}

extension StatusItemLabel {
    /// The row as a non-template image, ready for `MenuBarExtra`'s label.
    ///
    /// `isTemplate = false` is what keeps the colours — and the cost of that
    /// is real: the system no longer recolours the label when the menu bar
    /// flips between light and dark, so the caller has to redraw on an
    /// appearance change. `PanelModel.updateStatusImage()` does.
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
