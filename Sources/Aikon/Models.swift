import Foundation

enum SessionStatus: Equatable {
    case needsPermission   // ⚠️
    case needsAnswer       // ❓
    case finished          // 🏁
    case working

    var glyph: String {
        switch self {
        case .needsPermission: "⚠️"
        case .needsAnswer:     "❓"
        case .finished:        "🏁"
        case .working:         "●"
        }
    }

    var words: String {
        switch self {
        case .needsPermission: L.string("status.needsPermission")
        case .needsAnswer:     L.string("status.needsAnswer")
        case .finished:        L.string("status.finished")
        case .working:         L.string("status.working")
        }
    }

    var waitsForHer: Bool { self == .needsPermission || self == .needsAnswer }

    /// How urgent the status is — used to pick what to show when one folder
    /// has several transcripts.
    var urgency: Int {
        switch self {
        case .needsPermission, .needsAnswer: 3
        case .finished:                      2
        case .working:                       1
        }
    }
}

struct Session: Identifiable, Equatable {
    let id: String          // uuid
    let path: String        // working folder
    let status: SessionStatus
    let since: Date         // when it entered this status
    let touched: Date       // when the transcript was last written to
    var project: Project?
    var branch: String?
}
