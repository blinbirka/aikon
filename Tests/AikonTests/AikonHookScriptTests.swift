import Testing
import Foundation

// Runs the bundled shell hook (Sources/Aikon/Resources/hook/aikon-hook.sh)
// directly with /bin/sh's toolchain, the way Claude Code itself invokes it —
// no Swift, no XCTest fixture, just stdin JSON and a temp $HOME. This is what
// guards against the script quietly depending on python3 again: on a stock
// macOS with nothing beyond the base system installed, there is no python3,
// and the script is written to always exit 0, so a silent regression there
// would otherwise never surface as a test failure.

private func hookScriptURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // this file -> Tests/AikonTests
        .deletingLastPathComponent() // -> Tests
        .deletingLastPathComponent() // -> repo root
        .appendingPathComponent("Sources/Aikon/Resources/hook/aikon-hook.sh")
}

private func tempHome() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "aikon-hook-script-test-\(UUID())")
}

private func stateDir(under home: URL) -> URL {
    home.appending(path: ".claude/tools/notify/state")
}

/// Runs the hook script with `payload` on stdin and `arg` (if any) as $1,
/// against a throwaway $HOME. Returns the process exit code; the caller
/// inspects the state directory for marker files.
@discardableResult
private func runHook(payload: String, arg: String? = nil, home: URL, extraPath: String? = nil) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    var args = [hookScriptURL().path]
    if let arg { args.append(arg) }
    process.arguments = args

    var env = ProcessInfo.processInfo.environment
    env["HOME"] = home.path
    if let extraPath { env["PATH"] = extraPath }
    process.environment = env

    let stdin = Pipe()
    process.standardInput = stdin
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    try process.run()
    stdin.fileHandleForWriting.write(Data(payload.utf8))
    try stdin.fileHandleForWriting.close()
    process.waitUntilExit()
    return process.terminationStatus
}

/// `true` when /bin/bash exists and is runnable, so these tests degrade to a
/// skip instead of a hard failure on a system where it's somehow missing.
private func shellIsAvailable() -> Bool {
    FileManager.default.isExecutableFile(atPath: "/bin/bash")
}

@Suite(.serialized)
struct AikonHookScriptTests {

    @Test func writesPermissionMarkerForExplicitPermissionArg() throws {
        try #require(shellIsAvailable())
        let home = tempHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let status = try runHook(
            payload: #"{"session_id":"sess-1","hook_event_name":"Notification"}"#,
            arg: "permission",
            home: home
        )

        #expect(status == 0)
        #expect(FileManager.default.fileExists(atPath: stateDir(under: home).appending(path: "sess-1.⚠️").path))
    }

    @Test func writesAnswerMarkerForExplicitAnswerArg() throws {
        try #require(shellIsAvailable())
        let home = tempHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let status = try runHook(
            payload: #"{"session_id":"sess-2","hook_event_name":"Notification"}"#,
            arg: "answer",
            home: home
        )

        #expect(status == 0)
        #expect(FileManager.default.fileExists(atPath: stateDir(under: home).appending(path: "sess-2.❓").path))
    }

    @Test func writesDoneAndQuietMarkersForExplicitDoneArg() throws {
        try #require(shellIsAvailable())
        let home = tempHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let status = try runHook(
            payload: #"{"session_id":"sess-3","hook_event_name":"Stop"}"#,
            arg: "done",
            home: home
        )

        #expect(status == 0)
        #expect(FileManager.default.fileExists(atPath: stateDir(under: home).appending(path: "sess-3.🏁").path))
        #expect(FileManager.default.fileExists(atPath: stateDir(under: home).appending(path: "sess-3.quiet").path))
    }

    @Test func fallsBackToEventNameWhenInvokedWithoutAnArgument() throws {
        try #require(shellIsAvailable())
        let home = tempHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let status = try runHook(
            payload: #"{ "session_id" : "sess-4" , "hook_event_name" : "PermissionRequest" }"#,
            home: home
        )

        #expect(status == 0)
        #expect(FileManager.default.fileExists(atPath: stateDir(under: home).appending(path: "sess-4.⚠️").path))
    }

    @Test func elicitationEventWritesAnswerMarker() throws {
        try #require(shellIsAvailable())
        let home = tempHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let status = try runHook(
            payload: #"{"session_id":"sess-5","hook_event_name":"Elicitation"}"#,
            home: home
        )

        #expect(status == 0)
        #expect(FileManager.default.fileExists(atPath: stateDir(under: home).appending(path: "sess-5.❓").path))
    }

    @Test func parsesJSONWithoutPython3OnThePath() throws {
        try #require(shellIsAvailable())
        let home = tempHome()
        defer { try? FileManager.default.removeItem(at: home) }

        // Same shape of PATH a stock macOS with no developer tools would
        // have: no python3 anywhere on it. This is the regression the whole
        // script rewrite exists to fix.
        let status = try runHook(
            payload: #"{"session_id":"sess-6","hook_event_name":"Stop"}"#,
            home: home,
            extraPath: "/usr/bin:/bin"
        )

        #expect(status == 0)
        #expect(FileManager.default.fileExists(atPath: stateDir(under: home).appending(path: "sess-6.🏁").path))
    }

    @Test func malformedJSONExitsCleanlyAndWritesNothing() throws {
        try #require(shellIsAvailable())
        let home = tempHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let status = try runHook(payload: "{ not valid json at all", home: home)

        #expect(status == 0)
        #expect(!FileManager.default.fileExists(atPath: stateDir(under: home).path)
                || (try? FileManager.default.contentsOfDirectory(atPath: stateDir(under: home).path).isEmpty) == true)
    }

    @Test func emptyPayloadExitsCleanlyAndWritesNothing() throws {
        try #require(shellIsAvailable())
        let home = tempHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let status = try runHook(payload: "", home: home)

        #expect(status == 0)
        #expect(!FileManager.default.fileExists(atPath: stateDir(under: home).path)
                || (try? FileManager.default.contentsOfDirectory(atPath: stateDir(under: home).path).isEmpty) == true)
    }

    @Test func missingSessionIdExitsCleanlyAndWritesNothing() throws {
        try #require(shellIsAvailable())
        let home = tempHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let status = try runHook(
            payload: #"{"hook_event_name":"Notification"}"#,
            arg: "permission",
            home: home
        )

        #expect(status == 0)
        #expect(!FileManager.default.fileExists(atPath: stateDir(under: home).path)
                || (try? FileManager.default.contentsOfDirectory(atPath: stateDir(under: home).path).isEmpty) == true)
    }

    @Test func sessionIdContainingASlashIsRejected() throws {
        try #require(shellIsAvailable())
        let home = tempHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let status = try runHook(
            payload: #"{"session_id":"evil/../../etc","hook_event_name":"Notification"}"#,
            arg: "permission",
            home: home
        )

        #expect(status == 0)
        // Nothing written inside the intended state dir, and nothing
        // written anywhere else under the fake $HOME either.
        let writtenAnywhere = (try? FileManager.default.subpathsOfDirectory(atPath: home.path))?
            .contains { $0.contains("evil") } ?? false
        #expect(!writtenAnywhere)
    }
}
