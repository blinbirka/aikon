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
        case .needsAnswer:     .red
        case .needsPermission: .yellow
        case .finished:        .green
        case .working:         Theme.textFaint
        }
    }
}
