import Testing
@testable import Aikon
import Foundation

// `GitBranch` shells out to `/usr/bin/git branch --show-current`, with a
// 30-second in-memory cache per path. Every real-repo test below builds its
// own throwaway repository under a temp directory with `Process` — never the
// real home directory or the checkout this test suite itself lives in — and
// removes it afterwards. Every git command is scoped with `-C <tmp>` and
// `user.email`/`user.name` are set locally in that one repo, never touching
// global git config.

private let gitBinary = "/usr/bin/git"

/// True when `/usr/bin/git` exists on this machine. Tests that need to run a
/// real repo skip (return without asserting) when it's missing, per the task
/// instructions, rather than failing the whole suite on a machine without it.
private var hasGit: Bool { FileManager.default.fileExists(atPath: gitBinary) }

@discardableResult
private func runGit(_ arguments: [String], in dir: URL) throws -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: gitBinary)
    p.arguments = arguments
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    try p.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

/// A real git repo in a temp directory, with one commit on a known,
/// explicitly-created branch (`aikon-test`) rather than trusting whatever the
/// machine's `init.defaultBranch` happens to be.
private func makeRepo(branch: String = "aikon-test") throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("aikon-gitbranch-test-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try runGit(["-C", dir.path, "init", "-q"], in: dir)
    try runGit(["-C", dir.path, "config", "user.email", "test@example.com"], in: dir)
    try runGit(["-C", dir.path, "config", "user.name", "Aikon Test"], in: dir)
    try Data("hello".utf8).write(to: dir.appendingPathComponent("file.txt"))
    try runGit(["-C", dir.path, "add", "file.txt"], in: dir)
    try runGit(["-C", dir.path, "commit", "-q", "-m", "init"], in: dir)
    try runGit(["-C", dir.path, "checkout", "-q", "-b", branch], in: dir)
    return dir
}

@Test func aDirectoryThatIsNotAGitRepoReturnsNil() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("aikon-gitbranch-plain-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let branch = await GitBranch().branch(at: dir.path)
    #expect(branch == nil)
}

@Test func aPathThatDoesNotExistAtAllReturnsNil() async {
    let missing = FileManager.default.temporaryDirectory
        .appendingPathComponent("aikon-gitbranch-missing-\(UUID())").path
    let branch = await GitBranch().branch(at: missing)
    #expect(branch == nil)
}

@Test func aRealRepoReturnsItsCurrentBranchName() async throws {
    guard hasGit else { return }  // no git on this machine — nothing to verify
    let dir = try makeRepo(branch: "aikon-test")
    defer { try? FileManager.default.removeItem(at: dir) }

    // Read the branch back with git itself rather than assuming the name we
    // asked for stuck, per the task's "prefer the explicit branch" guidance.
    let expected = try runGit(["-C", dir.path, "branch", "--show-current"], in: dir)
    #expect(expected == "aikon-test")

    let branch = await GitBranch().branch(at: dir.path)
    #expect(branch == expected)
}

/// Two calls in a row for the same path hit the 30-second cache: proven here
/// by changing the branch on disk between the two calls and checking the
/// second call still returns the FIRST value instead of the new one.
@Test func repeatedCallsWithinTheCacheWindowReturnTheSameValue() async throws {
    guard hasGit else { return }  // no git on this machine — nothing to verify
    let dir = try makeRepo(branch: "aikon-test")
    defer { try? FileManager.default.removeItem(at: dir) }

    let gitBranch = GitBranch()
    let first = await gitBranch.branch(at: dir.path)
    #expect(first == "aikon-test")

    try runGit(["-C", dir.path, "checkout", "-q", "-b", "aikon-test-second"], in: dir)
    let afterSwitch = try runGit(["-C", dir.path, "branch", "--show-current"], in: dir)
    #expect(afterSwitch == "aikon-test-second")  // the repo really did change branch

    let second = await gitBranch.branch(at: dir.path)
    #expect(second == first)  // still the cached, stale answer
}
