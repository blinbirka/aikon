import Foundation

/// How three sources — the marker in notify/state, the .quiet sentinel, and the
/// last transcript write — collapse into a single menu row status.
/// Kept separate because this is the one place where the panel makes a
/// decision, and it needs to be testable without a filesystem.
enum StatusRules {
    /// A marker is trusted only if nothing was written to the transcript after
    /// it: notify.sh never deletes ⚠️ and ❓, and they can stick around for hours.
    /// The 10-second slack accounts for the gap between the transcript write and
    /// the hook firing.
    static let markerSlack: TimeInterval = 10

    struct Input {
        let touched: Date        // last write to the transcript
        let marker: StateFile?   // this session's freshest ⚠️ / ❓ / 🏁
        let quiet: Date?         // {uuid}.quiet sentinel
        let working: Bool?       // what the transcript tail says; nil — nothing to say
    }

    /// nil means "there is no session": the transcript had no Claude entries at
    /// all. Such files do occur — a window opened, a prompt was written, no reply
    /// ever came — and they used to show up as "working" for hours.
    static func decide(_ input: Input) -> (status: SessionStatus, since: Date)? {
        if let marker = input.marker,
           marker.at.addingTimeInterval(markerSlack) >= input.touched {
            return (marker.status, marker.at)
        }
        // Spelled `.some`/`.none` rather than `true`/`false`/`nil`: Swift 6.3
        // accepts the short form as exhaustive, Swift 6.1 does not, and the
        // short form made the package impossible to build on Xcode 16.
        switch input.working {
        case .some(true):
            return (.working, input.touched)
        case .some(false):
            // The sentinel can be left over from a previous turn if its process
            // was killed. It shows the correct end time only when it isn't older
            // than the last transcript write — a stale .quiet can lag hours
            // behind the actual last activity.
            let since = (input.quiet.map { $0 >= input.touched ? $0 : input.touched })
                ?? input.touched
            return (.finished, since)
        case .none:
            return nil
        }
    }
}
