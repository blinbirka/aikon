import Testing
@testable import Aikon
import Foundation

private func session(_ id: String, _ status: SessionStatus, minutesAgo: Double) -> Session {
    let t = Date().addingTimeInterval(-minutesAgo * 60)
    return Session(id: id, path: "/Users/example/Projects/x", status: status, since: t, touched: t)
}

private func representative(_ group: [Session]) -> Session? {
    group.max { a, b in
        (a.status.waitsForHer ? 1 : 0, a.touched) < (b.status.waitsForHer ? 1 : 0, b.touched)
    }
}

/// A request for a decision wins even over the freshest record: the marker only
/// counts if nothing was written to the transcript after it — it can't go stale.
@Test func requestForDecisionAlwaysWins() {
    let group = [session("working", .working, minutesAgo: 0),
                 session("finished", .finished, minutesAgo: 18),
                 session("waiting", .needsPermission, minutesAgo: 40)]
    #expect(representative(group)?.id == "waiting")
}

@Test func liveWorkOutranksFinishedWork() {
    // two sessions where one wrote in the very same second, and the row still
    // showed "finished 39 minutes ago"
    let group = [session("working", .working, minutesAgo: 0),
                 session("finished", .finished, minutesAgo: 39)]
    #expect(representative(group)?.id == "working")
}

@Test func finishedOutranksLongSilentWork() {
    let group = [session("working", .working, minutesAgo: 300),
                 session("finished", .finished, minutesAgo: 4)]
    #expect(representative(group)?.id == "finished")
}

@Test func allElseEqualFreshestWins() {
    let group = [session("old", .finished, minutesAgo: 300),
                 session("fresh", .finished, minutesAgo: 4)]
    #expect(representative(group)?.id == "fresh")
}
