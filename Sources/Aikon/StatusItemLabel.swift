import SwiftUI

struct Counts: Equatable {
    var waiting = 0   // needs permission + needs answer
    var done = 0
    var busy = 0
}

/// The three pairs in the menu bar.
///
/// This is a live view, hosted inside the status item by `StatusBarController`
/// — not a `MenuBarExtra` label, and not a picture. Both of those were tried
/// and both fail here, in ways worth writing down so they aren't tried again:
///
/// - A `MenuBarExtra` label takes text, an image, or text with an image. A
///   composed label is reduced to its first element, and symbols concatenated
///   into a `Text` are dropped entirely — that version showed the numbers and
///   none of the glyphs.
/// - A hand-drawn image of the whole row can hold the glyphs, but not the
///   colours *and* the legibility. Marked as a template it is tinted correctly
///   and loses every colour; marked as anything else it keeps the colours and
///   is never tinted — and the menu bar is translucent, so what sits behind
///   the numbers is the desktop picture. There is no fixed colour that works
///   on all of them, and macOS does not report which one it drew.
///
/// A live view escapes that: it sits inside the status item's own window,
/// which carries the vibrant appearance the system uses for the real menu
/// bar, so `.primary` follows the bar the way system text does, while the
/// symbols keep the colours given to them.
struct StatusItemLabel: View {
    let counts: Counts
    /// Given, not inherited. `.primary` here is drawn with the menu bar's
    /// vibrancy: correct on screen, but it does not survive an offscreen copy,
    /// so nothing about this label could be checked without asking a person to
    /// look at it. `StatusBarController` reads the real appearance off the
    /// status item's button — which, unlike the application's, follows the bar
    /// the system actually drew — and passes the colour in.
    var numberColour: Color = .primary

    /// Spacing inside a pair, and between pairs — her pick out of three
    /// mock-ups, the tightest of them, because the menu bar is shared space.
    private let insidePair: CGFloat = 2
    private let betweenPairs: CGFloat = 10

    /// The dot is drawn small on purpose, and a small glyph in a box sized for
    /// the big ones carries empty space on both sides — which made the third
    /// pair look further away than the second. Giving the dot a box its own
    /// size fixes that on its own. Trimming the gap *as well* was one
    /// correction too many: the two together left the second number jammed
    /// against the dot, close enough to read as a cut-off digit.
    private let dotOpticalTrim: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            pair(.needsPermission, counts.waiting)
            pair(.finished, counts.done)
                .padding(.leading, betweenPairs)
            pair(.working, counts.busy)
                .padding(.leading, betweenPairs - dotOpticalTrim)
        }
        .font(.system(size: 13))
        .monospacedDigit()
    }

    private func pair(_ status: SessionStatus, _ count: Int) -> some View {
        HStack(spacing: insidePair) {
            glyph(status)
                .frame(width: status == .working ? 9 : 14)
            Text("\(count)")
                .foregroundStyle(numberColour)
        }
    }

    /// Palette rendering for the two symbols that carry an inner mark: in the
    /// `.fill` variants the tick and the exclamation are holes punched through
    /// the shape, so the wallpaper showed through them. Filling them black is
    /// what the emoji did. Both colours go in one call — a second
    /// `foregroundStyle` replaces this one rather than adding to it, which is
    /// how the glyphs once came out solid black and invisible.
    ///
    /// The working dot has a single layer, and palette's first colour would
    /// paint the whole disc, so it stays monochrome.
    @ViewBuilder
    private func glyph(_ status: SessionStatus) -> some View {
        if status == .working {
            Image(systemName: status.symbolName)
                .font(.system(size: 8))
                .foregroundStyle(status.symbolColor)
        } else {
            Image(systemName: status.symbolName)
                .font(.system(size: 12))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.black, status.symbolColor)
        }
    }
}

/// The same label, following a model. `StatusBarController` hosts this one so
/// the menu bar redraws itself when the counts change.
struct StatusItemLabelHost: View {
    @ObservedObject var model: PanelModel
    var numberColour: Color

    var body: some View {
        StatusItemLabel(counts: model.counts, numberColour: numberColour)
    }
}
