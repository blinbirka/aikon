import Testing
@testable import Aikon
import Foundation

// `TranscriptIndex.index()` — the directory walk. Its leaf helpers
// (`working(inTail:)`, `findCWD(in:)`, ...) are covered in
// `TranscriptIndexTests`; this file exercises the walk itself, against real
// temporary directories, the same way `ProjectPathsTests` does.

@MainActor
private func withFakeProjectsRoot(_ body: (URL) throws -> Void) rethrows {
    let box = FileManager.default.temporaryDirectory.appendingPathComponent("aikon-index-test-\(UUID())")
    try? FileManager.default.createDirectory(at: box, withIntermediateDirectories: true)
    let savedRoot = TranscriptIndex.root
    TranscriptIndex.root = box
    ProjectPaths.invalidateCache()
    // A running VS Code (or Cursor, ...) is machine state: force it off so
    // `windowOpen` in `index()` is always false and the 30-minute cutoff is
    // the only thing deciding whether a stale transcript survives.
    let savedIsRunning = OpenWindows.isVSCodeRunning
    OpenWindows.isVSCodeRunning = { false }
    OpenWindows.forgetCache()
    defer {
        TranscriptIndex.root = savedRoot
        ProjectPaths.invalidateCache()
        OpenWindows.isVSCodeRunning = savedIsRunning
        OpenWindows.forgetCache()
        try? FileManager.default.removeItem(at: box)
    }
    try body(box)
}

private func sessionFolder(in root: URL, name: String = UUID().uuidString) throws -> URL {
    let dir = root.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// A transcript with a `cwd` and one finished turn (`end_turn`), fresh enough
/// to be read as a real session. `mtime` drives both the freshness cutoff and
/// which of several files for the same uuid is "the freshest".
@discardableResult
private func writeTranscript(in dir: URL, uuid: String = UUID().uuidString,
                             cwd: String, mtime: Date) throws -> URL {
    let file = dir.appendingPathComponent("\(uuid).jsonl")
    let lines = [#"{"type":"user","cwd":"\#(cwd)"}"#,
                 #"{"type":"assistant","message":{"stop_reason":"end_turn"}}"#]
    try Data(lines.joined(separator: "\n").utf8).write(to: file)
    try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: file.path)
    return file
}

private func realFolder(in root: URL, name: String) throws -> String {
    let dir = root.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return ProjectMatching.normalize(dir.path)
}

@Test @MainActor func noProjectsRootOnDiskGivesAnEmptyIndex() {
    withFakeProjectsRoot { box in
        TranscriptIndex.root = box.appendingPathComponent("does-not-exist")
        #expect(TranscriptIndex.index(now: Date()).isEmpty)
    }
}

@Test @MainActor func emptySessionFolderGivesNoEntries() throws {
    try withFakeProjectsRoot { box in
        _ = try sessionFolder(in: box)
        #expect(TranscriptIndex.index(now: Date()).isEmpty)
    }
}

@Test @MainActor func aTranscriptWhoseFolderNoLongerExistsIsSkipped() throws {
    try withFakeProjectsRoot { box in
        let dir = try sessionFolder(in: box)
        let vanished = box.appendingPathComponent("vanished-project").path
        try writeTranscript(in: dir, cwd: vanished, mtime: Date())
        #expect(TranscriptIndex.index(now: Date()).isEmpty)
    }
}

/// A closed window's transcript is still shown for up to 30 minutes of
/// silence — a session isn't stale the instant it stops writing.
@Test @MainActor func transcriptTouched29MinutesAgoIsStillLive() throws {
    try withFakeProjectsRoot { box in
        let dir = try sessionFolder(in: box)
        let path = try realFolder(in: box, name: "project")
        let now = Date()
        let id = UUID().uuidString
        try writeTranscript(in: dir, uuid: id, cwd: path, mtime: now.addingTimeInterval(-29 * 60))

        let entries = TranscriptIndex.index(now: now)
        #expect(entries[id]?.path == path)
    }
}

/// One minute later, past the 30-minute cutoff, with no window open to keep
/// it alive: the same transcript drops out of the index.
@Test @MainActor func transcriptTouched31MinutesAgoIsStale() throws {
    try withFakeProjectsRoot { box in
        let dir = try sessionFolder(in: box)
        let path = try realFolder(in: box, name: "project")
        let now = Date()
        let id = UUID().uuidString
        try writeTranscript(in: dir, uuid: id, cwd: path, mtime: now.addingTimeInterval(-31 * 60))

        #expect(TranscriptIndex.index(now: now)[id] == nil)
    }
}

/// The same session uuid can exist in two project folders at once — a stub
/// left behind in a stale directory, and the real file in the current one.
/// Whichever copy is freshest wins, but only if its folder still exists: a
/// newer stub in a folder that's gone must not shadow the real, older one.
@Test @MainActor func sameUUIDInTwoFoldersPicksTheFreshestExistingOne() throws {
    try withFakeProjectsRoot { box in
        let id = UUID().uuidString
        let now = Date()
        let real = try realFolder(in: box, name: "real-project")

        // The newer copy lives in a folder that's since been removed —
        // its transcript must lose to the older, still-real one.
        let staleDir = try sessionFolder(in: box, name: "stale-session-dir")
        let removed = box.appendingPathComponent("removed-project").path
        try writeTranscript(in: staleDir, uuid: id, cwd: removed,
                            mtime: now.addingTimeInterval(-5 * 60))

        let currentDir = try sessionFolder(in: box, name: "current-session-dir")
        try writeTranscript(in: currentDir, uuid: id, cwd: real,
                            mtime: now.addingTimeInterval(-20 * 60))

        let entries = TranscriptIndex.index(now: now)
        #expect(entries[id]?.path == real)
    }
}

/// Same setup, but both copies point at folders that still exist: now the
/// freshest one is simply the right answer, not a fallback.
@Test @MainActor func sameUUIDInTwoFoldersBothRealPicksTheFreshest() throws {
    try withFakeProjectsRoot { box in
        let id = UUID().uuidString
        let now = Date()
        let older = try realFolder(in: box, name: "older-project")
        let newer = try realFolder(in: box, name: "newer-project")

        try writeTranscript(in: try sessionFolder(in: box), uuid: id, cwd: older,
                            mtime: now.addingTimeInterval(-20 * 60))
        try writeTranscript(in: try sessionFolder(in: box), uuid: id, cwd: newer,
                            mtime: now.addingTimeInterval(-5 * 60))

        let entries = TranscriptIndex.index(now: now)
        #expect(entries[id]?.path == newer)
    }
}

@Test @MainActor func severalLiveSessionsAreAllReturnedByTheirOwnUUID() throws {
    try withFakeProjectsRoot { box in
        let now = Date()
        let p1 = try realFolder(in: box, name: "one")
        let p2 = try realFolder(in: box, name: "two")
        let id1 = UUID().uuidString
        let id2 = UUID().uuidString
        try writeTranscript(in: try sessionFolder(in: box), uuid: id1, cwd: p1, mtime: now)
        try writeTranscript(in: try sessionFolder(in: box), uuid: id2, cwd: p2, mtime: now)

        let entries = TranscriptIndex.index(now: now)
        #expect(entries.count == 2)
        #expect(entries[id1]?.path == p1)
        #expect(entries[id2]?.path == p2)
    }
}
