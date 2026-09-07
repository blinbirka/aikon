import SwiftUI

struct Counts: Equatable {
    var waiting = 0   // needs permission + needs answer
    var done = 0
    var busy = 0
}

struct StatusItemLabel: View {
    let counts: Counts

    var body: some View {
        // MenuBarExtra only renders the label reliably with a single Text: with a
        // composite HStack, the system truncates it down to the first element —
        // the menu bar would show only the first glyph, with no numbers.
        //
        // Which is why the symbols are concatenated *into* the Text rather than
        // placed beside it: `Text(Image(systemName:))` keeps the whole label one
        // Text, and a per-segment `.foregroundColor` is the one way to colour
        // parts of it differently.
        (symbol(.needsPermission) + Text("\(counts.waiting)  ")
         + symbol(.finished) + Text("\(counts.done)  ")
         + symbol(.working) + Text("\(counts.busy)"))
            .monospacedDigit()
    }

    private func symbol(_ status: SessionStatus) -> Text {
        Text(Image(systemName: status.symbolName))
            .foregroundColor(status.symbolColor)
    }
}
