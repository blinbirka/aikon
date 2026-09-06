import Testing
@testable import Aikon
import Foundation

// `ProjectPaths.knownPaths()` reads `TranscriptIndex.root` directly, the same
// mutable-static injection style `StateReader.dir` already uses — see
// `StateFreshnessTests`. Every test below points it at a throwaway directory
// tree and restores the real root and cache on the way out.

@MainActor
private func withFakeProjectsRoot(_ body: (URL) throws -> Void) rethrows {
    let box = FileManager.default.temporaryDirectory.appendingPathComponent("aikon-paths-test-\(UUID())")
    try? FileManager.default.createDirectory(at: box, withIntermediateDirectories: true)
    let savedRoot = TranscriptIndex.root
    TranscriptIndex.root = box
    ProjectPaths.invalidateCache()
    defer {
        TranscriptIndex.root = savedRoot
        ProjectPaths.invalidateCache()
        try? FileManager.default.removeItem(at: box)
    }
    try body(box)
}

/// One hashed session folder under the fake root, holding whatever
/// transcripts a test writes into it.
private func sessionFolder(in root: URL, name: String = UUID().uuidString) throws -> URL {
    let dir = root.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// A minimal transcript: one line with a `cwd`, enough for
/// `TranscriptIndex.cwd(ofTranscript:)` to find it. `mtime` drives the
/// "8 most recent files" ordering.
@discardableResult
private func writeTranscript(in dir: URL, cwd: String, mtime: Date) throws -> URL {
    let file = dir.appendingPathComponent("\(UUID()).jsonl")
    try Data(#"{"type":"user","cwd":"\#(cwd)"}"#.utf8).write(to: file)
    try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: file.path)
    return file
}

/// A real directory a transcript's `cwd` can point at — `knownPaths()` drops
/// any cwd whose folder no longer exists.
private func realFolder(in root: URL, name: String) throws -> String {
    let dir = root.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return ProjectMatching.normalize(dir.path)   // matches what TranscriptIndex.cwd resolves to
}

@Test @MainActor func noProjectsRootOnDiskGivesAnEmptyList() {
    withFakeProjectsRoot { box in
        TranscriptIndex.root = box.appendingPathComponent("does-not-exist")
        #expect(ProjectPaths.knownPaths(now: Date()) == [])
    }
}

@Test @MainActor func emptySessionFolderContributesNothing() throws {
    try withFakeProjectsRoot { box in
        _ = try sessionFolder(in: box)   // exists, but no .jsonl in it
        #expect(ProjectPaths.knownPaths(now: Date()) == [])
    }
}

@Test @MainActor func aCwdWhoseFolderNoLongerExistsIsDropped() throws {
    try withFakeProjectsRoot { box in
        let dir = try sessionFolder(in: box)
        let vanished = box.appendingPathComponent("vanished-project").path
        try writeTranscript(in: dir, cwd: vanished, mtime: Date())
        #expect(ProjectPaths.knownPaths(now: Date()) == [])
    }
}

/// Only the 8 most recent files in a session folder are examined, and among
/// those, the first (freshest-first) whose folder still exists wins — even
/// when an older, existing folder is sitting right behind the cutoff.
@Test @MainActor func picksTheFreshestExistingFolderWithinTheEightMostRecentFiles() throws {
    try withFakeProjectsRoot { box in
        let dir = try sessionFolder(in: box)
        let now = Date()
        let valid = try realFolder(in: box, name: "valid-inside-window")
        let outside = try realFolder(in: box, name: "valid-outside-window")

        // 10 files, newest to oldest: index 0 is freshest. Everything in the
        // top 8 (indices 0...7) points nowhere real except index 4. Index 8
        // — one past the window — points at a real folder too, and must be
        // ignored because it's never looked at.
        for i in 0..<10 {
            let cwd = (i == 4) ? valid : (i == 8) ? outside
                : box.appendingPathComponent("gone-\(i)").path
            try writeTranscript(in: dir, cwd: cwd, mtime: now.addingTimeInterval(-Double(i)))
        }

        #expect(ProjectPaths.knownPaths(now: now) == [valid])
    }
}

@Test @MainActor func resultIsSortedShortestPathFirst() throws {
    try withFakeProjectsRoot { box in
        let short = try realFolder(in: box, name: "app")
        let long = try realFolder(in: box, name: "app-with-a-much-longer-folder-name")
        try writeTranscript(in: try sessionFolder(in: box), cwd: short, mtime: Date())
        try writeTranscript(in: try sessionFolder(in: box), cwd: long, mtime: Date())

        #expect(ProjectPaths.knownPaths(now: Date()) == [short, long])
    }
}

@Test @MainActor func equalLengthPathsAreSortedAlphabetically() throws {
    try withFakeProjectsRoot { box in
        let bbbb = try realFolder(in: box, name: "bbbb")
        let aaaa = try realFolder(in: box, name: "aaaa")
        try writeTranscript(in: try sessionFolder(in: box), cwd: bbbb, mtime: Date())
        try writeTranscript(in: try sessionFolder(in: box), cwd: aaaa, mtime: Date())

        #expect(ProjectPaths.knownPaths(now: Date()) == [aaaa, bbbb])
    }
}

/// The list is rebuilt at most once every 5 minutes: a folder added in
/// between doesn't show up until the cache expires.
@Test @MainActor func cachedAnswerIsReusedUntilTheTTLExpiresThenRebuilds() throws {
    try withFakeProjectsRoot { box in
        let first = try realFolder(in: box, name: "first-project")
        try writeTranscript(in: try sessionFolder(in: box), cwd: first, mtime: Date())

        let t0 = Date()
        #expect(ProjectPaths.knownPaths(now: t0) == [first])

        // Added to disk after the first (cached) read.
        let second = try realFolder(in: box, name: "second-project")
        try writeTranscript(in: try sessionFolder(in: box), cwd: second, mtime: t0)

        #expect(ProjectPaths.knownPaths(now: t0.addingTimeInterval(100)) == [first])
        #expect(Set(ProjectPaths.knownPaths(now: t0.addingTimeInterval(301))) == Set([first, second]))
    }
}
