import Testing
@testable import Aikon
import Foundation

private let t0 = Date(timeIntervalSince1970: 1_788_400_000)

@Test func markerFresherThanTheRecordCounts() {
    // Claude asked for permission and went quiet: the transcript and the marker are the same age.
    let v = StatusRules.decide(.init(touched: t0,
                                     marker: StateFile(uuid: "a", status: .needsPermission, at: t0),
                                     quiet: nil, working: nil))
    #expect(v?.status == .needsPermission)
    #expect(v?.since == t0)
}

@Test func markerOlderThanTheRecordDoesNotCount() {
    // State files are never deleted: a ⚠️ marker sat there for 7 hours while
    // the transcript had a write ten minutes ago.
    let v = StatusRules.decide(.init(touched: t0,
                                     marker: StateFile(uuid: "a", status: .needsPermission,
                                                       at: t0.addingTimeInterval(-7 * 3600)),
                                     quiet: nil, working: true))
    #expect(v?.status == .working)
}

@Test func watchdogOlderThanTheLastRecordIsIgnored() {
    // real case: .quiet at 6.7 hours while the transcript was at 5.3 — the panel
    // would have shown "finished 6 h" instead of "5 h".
    let v = StatusRules.decide(.init(touched: t0,
                                     marker: nil,
                                     quiet: t0.addingTimeInterval(-5000),
                                     working: false))
    #expect(v?.status == .finished)
    #expect(v?.since == t0)
}

@Test func freshWatchdogGivesTheMomentItFinished() {
    let quiet = t0.addingTimeInterval(3)
    let v = StatusRules.decide(.init(touched: t0, marker: nil, quiet: quiet, working: false))
    #expect(v?.since == quiet)
}

@Test func transcriptWithNoClaudeRecordsIsNotASession() {
    // Window opened, a prompt was typed, no reply ever came. Such sessions used
    // to show "working" for nine hours straight — a 16 KB transcript, not one
    // assistant record in it.
    #expect(StatusRules.decide(.init(touched: t0, marker: nil, quiet: nil, working: nil)) == nil)
}

@Test func toolCallCountsAsWork() {
    let v = StatusRules.decide(.init(touched: t0, marker: nil, quiet: nil, working: true))
    #expect(v?.status == .working)
    #expect(v?.since == t0)
}
