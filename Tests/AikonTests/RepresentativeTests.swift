import Testing
@testable import Aikon
import Foundation

// Exercises the real comparator PanelModel.refresh() uses to pick which of
// several sessions in the same folder becomes the menu row — not a copy of
// it. A copy here would stay green even if the real comparator broke.

private func session(_ id: String, _ status: SessionStatus, minutesAgo: Double) -> Session {
    let t = Date().addingTimeInterval(-minutesAgo * 60)
    return Session(id: id, path: "/Users/example/Projects/x", status: status, since: t, touched: t)
}

/// A request for a decision wins even over the freshest record: the marker only
/// counts if nothing was written to the transcript after it — it can't go stale.
@Test @MainActor func requestForDecisionAlwaysWins() {
    let group = [session("working", .working, minutesAgo: 0),
                 session("finished", .finished, minutesAgo: 18),
                 session("waiting", .needsPermission, minutesAgo: 40)]
    #expect(PanelModel.representative(of: group)?.id == "waiting")
}

@Test @MainActor func liveWorkOutranksFinishedWork() {
    // two sessions where one wrote in the very same second, and the row still
    // showed "finished 39 minutes ago"
    let group = [session("working", .working, minutesAgo: 0),
                 session("finished", .finished, minutesAgo: 39)]
    #expect(PanelModel.representative(of: group)?.id == "working")
}

@Test @MainActor func finishedOutranksLongSilentWork() {
    let group = [session("working", .working, minutesAgo: 300),
                 session("finished", .finished, minutesAgo: 4)]
    #expect(PanelModel.representative(of: group)?.id == "finished")
}

@Test @MainActor func allElseEqualFreshestWins() {
    let group = [session("old", .finished, minutesAgo: 300),
                 session("fresh", .finished, minutesAgo: 4)]
    #expect(PanelModel.representative(of: group)?.id == "fresh")
}

@Test @MainActor func emptyGroupHasNoRepresentative() {
    #expect(PanelModel.representative(of: []) == nil)
}
