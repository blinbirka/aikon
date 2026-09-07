import SwiftUI

/// How a status is drawn. Kept out of `SessionStatus` itself, which is
/// Foundation-only on purpose: the emoji that used to live there also spell
/// the state files' suffixes on disk (`.⚠️`, `.❓`, `.🏁` — written by
/// `aikon-hook.sh`, matched in `StateReader`). Those must not follow the
/// interface's taste, so the two are deliberately separate now.
///
/// SF Symbols rather than emoji: emoji are bitmaps, and the finely checkered
/// 🏁 in particular broke up into a grey smudge at menu-bar size and rippled
/// in the README picture. A symbol is a vector at every size. The colours stay
/// — they are what makes the four states readable out of the corner of an eye.
extension SessionStatus {
    var symbolName: String {
        switch self {
        case .needsAnswer:     "questionmark.circle.fill"
        case .needsPermission: "exclamationmark.triangle.fill"
        case .finished:        "checkmark.circle.fill"
        case .working:         "circle.fill"
        }
    }

    /// System colours, not `Theme`'s: these say "something needs you" / "this
    /// is done", the same meanings macOS spends these exact colours on, and
    /// they resolve correctly in both appearances on their own.
    var symbolColor: Color {
        switch self {
        // Blue, not red: a question is not a failure. Red was reading as
        // "something broke" when all the session wants is an answer — the
        // yellow triangle next to it already carries the one urgent state.
        // The same blue as the unread dot, rather than a second one: they
        // never share a row, and the shapes tell them apart.
        case .needsAnswer:     Color.themed(light: 0x1c6cf0, dark: 0x4f9bff)
        case .needsPermission: .yellow
        case .finished:        .green
        case .working:         Theme.textFaint
        }
    }
}
