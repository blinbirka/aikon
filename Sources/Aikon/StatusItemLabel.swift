import SwiftUI

struct Counts: Equatable {
    var waiting = 0   // ⚠️ permission + ❓ question
    var done = 0      // 🏁
    var busy = 0      // working
}

struct StatusItemLabel: View {
    let counts: Counts

    var body: some View {
        // MenuBarExtra only renders the label reliably with a single Text: with a
        // composite HStack, the system truncates it down to the first element —
        // the menu bar would show only ⚠️, with no numbers.
        Text("⚠️\(counts.waiting)  🏁\(counts.done)  ●\(counts.busy)")
            .monospacedDigit()
    }

}
