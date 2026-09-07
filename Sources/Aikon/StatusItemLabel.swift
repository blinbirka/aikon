import SwiftUI

struct Counts: Equatable {
    var waiting = 0   // needs permission + needs answer
    var done = 0
    var busy = 0
}

/// The menu bar label. A single `Text`, and that is load-bearing twice over.
///
/// `MenuBarExtra` reduces a composed label to its first element, so an HStack
/// of images and numbers shows only the first glyph. That much was known. The
/// part that cost a day: an image label — even one drawn by hand with the
/// whole row in it — is the wrong shape for this problem. Marked as a template
/// it loses the colours; marked as anything else it stops being tinted, and
/// the menu bar is translucent, so the background is the desktop picture and
/// no fixed colour is safe on it.
///
/// Text sidesteps both. The numbers are plain text and the system tints them
/// to the bar it actually drew, whatever is behind it. The emoji carry their
/// own colours and are not tinted at all. That is why this worked before it
/// was ever thought about, and why it is back.
///
/// The one real defect was 🏁: a fine checkerboard that turned to grey mush at
/// menu-bar size and rippled in the README picture. ✅ says the same thing with
/// one solid shape. Inside the menu, where the app owns the background, the
/// statuses are drawn as coloured SF Symbols instead — see `StatusSymbol`.
struct StatusItemLabel: View {
    let counts: Counts

    var body: some View {
        // Spacing is what the characters give: a thin space holds a count to
        // its own glyph, two ordinary ones separate the pairs. Her pick out of
        // three mock-ups was the tightest of them.
        Text("⚠️\u{2009}\(counts.waiting)  ✅\u{2009}\(counts.done)  ●\u{2009}\(counts.busy)")
            .monospacedDigit()
    }
}
