import Testing
@testable import Aikon
import Foundation

/// `PanelModel`'s designated init defaults `configStore` to a real
/// `ConfigStore()`, which reads and seeds `~/.config/aikon/config.json` from
/// the real `~/.claude` and VS Code state the moment it's constructed — even
/// with `startRefreshing: false`. These tests only care about `seen`, so a
/// throwaway store pointed at a temp file, seeded from nothing, keeps them
/// off the real machine entirely. The temp file it seeds itself with is
/// removed again on the way out.
@MainActor
private func withThrowawayConfigStore(_ body: (ConfigStore) -> Void) {
    let box = FileManager.default.temporaryDirectory.appendingPathComponent("aikon-unread-test-\(UUID())")
    defer { try? FileManager.default.removeItem(at: box) }
    let store = ConfigStore(fileURL: box.appendingPathComponent("config.json"),
                            openFolders: { [] }, sessionFolders: { [] })
    body(store)
}

private func session(_ id: String, _ status: SessionStatus = .finished, minutesAgo: Double = 0) -> Session {
    let t = Date().addingTimeInterval(-minutesAgo * 60)
    return Session(id: id, path: "/Users/example/Projects/x", status: status, since: t, touched: t)
}

/// A plain in-memory stand-in for `UserDefaults`, conforming to the same
/// narrow `UnreadStore` protocol `PanelModel` actually depends on.
///
/// `UserDefaults(suiteName:)` was tried first, one throwaway suite per test —
/// but real `UserDefaults` round-trips through `cfprefsd`, a system daemon
/// that flushes `~/Library/Preferences/<suite>.plist` on its own asynchronous
/// schedule. A write already queued with the daemon could still land on disk
/// seconds after the test had already called `removePersistentDomain` and
/// deleted the file itself, leaving real files behind at random. This type
/// has no daemon, no disk, and nothing to leak.
final class InMemoryUnreadStore: UnreadStore {
    private var storage: [String: Any] = [:]
    func dictionary(forKey key: String) -> [String: Any]? { storage[key] as? [String: Any] }
    func set(_ value: Any?, forKey key: String) { storage[key] = value }
}

@Test @MainActor func finishedSessionNeverMarkedSeenIsUnread() {
    let defaults = InMemoryUnreadStore()
    withThrowawayConfigStore { store in
        let model = PanelModel(configStore: store, defaults: defaults, startRefreshing: false)
        #expect(model.isUnread(session("a")) == true)
    }
}

@Test @MainActor func onlyFinishedSessionsCanBeUnread() {
    let defaults = InMemoryUnreadStore()
    withThrowawayConfigStore { store in
        let model = PanelModel(configStore: store, defaults: defaults, startRefreshing: false)
        #expect(model.isUnread(session("a", .working)) == false)
        #expect(model.isUnread(session("a", .needsAnswer)) == false)
        #expect(model.isUnread(session("a", .needsPermission)) == false)
    }
}

@Test @MainActor func markingSeenClearsUnread() {
    let defaults = InMemoryUnreadStore()
    withThrowawayConfigStore { store in
        let model = PanelModel(configStore: store, defaults: defaults, startRefreshing: false)
        let s = session("a")
        #expect(model.isUnread(s) == true)
        model.markSeen(s)
        #expect(model.isUnread(s) == false)
    }
}

/// The same session id finishing again later — a new turn after the mark —
/// must show as unread again: `since` moved past `openedAt`.
@Test @MainActor func aSessionFinishingAgainAfterBeingSeenIsUnreadAgain() {
    let defaults = InMemoryUnreadStore()
    withThrowawayConfigStore { store in
        let model = PanelModel(configStore: store, defaults: defaults, startRefreshing: false)
        let now = Date()
        let firstFinish = session("a", .finished, minutesAgo: 20)
        model.markSeen(firstFinish, now: now.addingTimeInterval(-20 * 60))
        let secondFinish = session("a", .finished, minutesAgo: 0)
        #expect(model.isUnread(secondFinish) == true)
    }
}

/// Read marks are persisted, so an unread dot doesn't reappear after a restart.
///
/// `since` and the mark are a full minute apart on purpose: `markSeen` writes
/// through `UserDefaults` as a `Double` (`timeIntervalSince1970`), and a
/// round trip through that loses a little precision — asserting against
/// "now" on both sides made this flaky, occasionally landing the reloaded
/// mark a few microseconds before `since` instead of after it.
@Test @MainActor func seenStatePersistsAcrossInstancesInTheSameDefaults() {
    let defaults = InMemoryUnreadStore()
    withThrowawayConfigStore { firstStore in
        let first = PanelModel(configStore: firstStore, defaults: defaults, startRefreshing: false)
        let s = session("a", .finished, minutesAgo: 1)
        first.markSeen(s)

        withThrowawayConfigStore { secondStore in
            let second = PanelModel(configStore: secondStore, defaults: defaults, startRefreshing: false)
            #expect(second.isUnread(s) == false)
        }
    }
}

/// The read-marks list is unbounded otherwise: `markSeen` prunes anything
/// older than 30 days every time it's called.
@Test @MainActor func readMarkOlderThan30DaysIsPrunedAndSessionIsUnreadAgain() {
    let defaults = InMemoryUnreadStore()
    withThrowawayConfigStore { store in
        let model = PanelModel(configStore: store, defaults: defaults, startRefreshing: false)
        let now = Date()
        let old = session("old")
        model.markSeen(old, now: now.addingTimeInterval(-31 * 24 * 60 * 60))

        // Pruning happens as a side effect of the NEXT markSeen call, with
        // a second, unrelated session — this is what actually runs on a
        // live app, since markSeen only ever fires from a click.
        model.markSeen(session("other"), now: now)

        #expect(model.isUnread(old) == true)
    }
}

/// One day short of the cutoff: the mark must survive the same prune.
@Test @MainActor func readMarkJustUnder30DaysSurvivesPruning() {
    let defaults = InMemoryUnreadStore()
    withThrowawayConfigStore { store in
        let model = PanelModel(configStore: store, defaults: defaults, startRefreshing: false)
        let now = Date()
        // Finished and opened at the same moment, 29 days ago — `since`
        // has to be at or before the mark, or the mark wouldn't clear
        // "unread" regardless of pruning.
        let openedAt = now.addingTimeInterval(-29 * 24 * 60 * 60)
        let recent = Session(id: "recent", path: "/Users/example/Projects/x",
                             status: .finished, since: openedAt, touched: openedAt)
        model.markSeen(recent, now: openedAt)

        model.markSeen(session("other"), now: now)

        #expect(model.isUnread(recent) == false)
    }
}
