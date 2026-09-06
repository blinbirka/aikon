import Testing
import Foundation
@testable import Aikon

// All of these run against throwaway files under a temp directory — never
// against the real ~/.claude/settings.json.

private func tempDir() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "aikon-hook-test-\(UUID())")
}

private func settingsURL(in dir: URL) -> URL {
    dir.appending(path: "settings.json")
}

private func hookDestURL(in dir: URL) -> URL {
    dir.appending(path: "aikon").appending(path: "aikon-hook.sh")
}

private func write(_ object: [String: Any], to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
}

private func readObject(at url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    return try JSONSerialization.jsonObject(with: data) as! [String: Any]
}

private func eventList(_ settings: [String: Any], _ event: String) -> [[String: Any]] {
    (settings["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
}

private func commands(_ entry: [String: Any]) -> [String] {
    ((entry["hooks"] as? [[String: Any]]) ?? []).compactMap { $0["command"] as? String }
}

@Test func installAddsOurHooksAndLeavesForeignHooksAlone() throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let settings = settingsURL(in: dir)

    let original: [String: Any] = [
        "someOtherTopLevelKey": "keep me",
        "hooks": [
            "PermissionRequest": [
                ["matcher": "someone_elses_matcher",
                 "hooks": [["type": "command", "command": "bash /other/hook.sh", "async": true]]]
            ],
            "PreToolUse": [
                ["hooks": [["type": "command", "command": "bash /other/pre.sh"]]]
            ],
        ],
    ]
    try write(original, to: settings)

    try HookInstaller.install(settingsURL: settings, hookDestURL: hookDestURL(in: dir))

    let result = try readObject(at: settings)
    #expect(result["someOtherTopLevelKey"] as? String == "keep me")

    // foreign PermissionRequest entry untouched, ours added alongside it
    let permission = eventList(result, "PermissionRequest")
    #expect(permission.count == 2)
    #expect(permission.contains { ($0["matcher"] as? String) == "someone_elses_matcher" })
    #expect(permission.contains { commands($0).contains { $0.contains("aikon-hook.sh") } })

    // untouched event stays exactly as it was
    let preToolUse = eventList(result, "PreToolUse")
    #expect(preToolUse.count == 1)
    #expect(commands(preToolUse[0]) == ["bash /other/pre.sh"])

    // every registration landed
    for reg in HookInstaller.registrations {
        let entries = eventList(result, reg.event)
        #expect(entries.contains { entry in
            let matcherOK = (entry["matcher"] as? String) == reg.matcher
            let cmdOK = commands(entry).contains { $0.contains("aikon-hook.sh") && $0.hasSuffix(" \(reg.arg)") }
            return matcherOK && cmdOK
        }, "missing registration for \(reg.event) matcher=\(String(describing: reg.matcher))")
    }
}

@Test func reinstallingUpdatesInPlaceWithoutDuplicating() throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let settings = settingsURL(in: dir)
    let dest = hookDestURL(in: dir)

    try HookInstaller.install(settingsURL: settings, hookDestURL: dest)
    try HookInstaller.install(settingsURL: settings, hookDestURL: dest)

    let result = try readObject(at: settings)
    for reg in HookInstaller.registrations {
        let entries = eventList(result, reg.event).filter { entry in
            (entry["matcher"] as? String) == reg.matcher && commands(entry).allSatisfy { $0.contains("aikon-hook.sh") }
        }
        #expect(entries.count == 1, "expected exactly one entry for \(reg.event) matcher=\(String(describing: reg.matcher)), found \(entries.count)")
    }
}

@Test func uninstallReturnsFileToItsOriginalState() throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let settings = settingsURL(in: dir)
    let dest = hookDestURL(in: dir)

    let original: [String: Any] = [
        "hooks": [
            "PreToolUse": [
                ["hooks": [["type": "command", "command": "bash /other/pre.sh"]]]
            ]
        ]
    ]
    try write(original, to: settings)

    try HookInstaller.install(settingsURL: settings, hookDestURL: dest)
    try HookInstaller.uninstall(settingsURL: settings, hookDestURL: dest)

    let result = try readObject(at: settings)
    #expect(NSDictionary(dictionary: result).isEqual(to: original))
    #expect(!FileManager.default.fileExists(atPath: dest.path))
}

@Test func uninstallWithNothingInstalledIsHarmless() throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let settings = settingsURL(in: dir)

    // no settings.json at all
    try HookInstaller.uninstall(settingsURL: settings, hookDestURL: hookDestURL(in: dir))
    #expect(!FileManager.default.fileExists(atPath: settings.path))
}

@Test func missingSettingsFileGetsCreatedWithHooksSection() throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let settings = settingsURL(in: dir)
    #expect(!FileManager.default.fileExists(atPath: settings.path))

    try HookInstaller.install(settingsURL: settings, hookDestURL: hookDestURL(in: dir))

    #expect(FileManager.default.fileExists(atPath: settings.path))
    let result = try readObject(at: settings)
    #expect(result["hooks"] != nil)
    #expect(eventList(result, "Stop").count == 1)
}

@Test func brokenJSONThrowsAndLeavesTheFileUntouched() throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let settings = settingsURL(in: dir)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let garbage = Data("{ not valid json at all".utf8)
    try garbage.write(to: settings)

    #expect(throws: HookInstaller.InstallerError.self) {
        try HookInstaller.install(settingsURL: settings, hookDestURL: hookDestURL(in: dir))
    }
    #expect((try? Data(contentsOf: settings)) == garbage)

    if case .unavailable = HookInstaller.state(settingsURL: settings) {
        // expected
    } else {
        Issue.record("expected .unavailable for broken JSON")
    }
}

@Test func backupFileIsCreatedBeforeWriting() throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let settings = settingsURL(in: dir)
    try write(["hooks": [:]], to: settings)

    try HookInstaller.install(settingsURL: settings, hookDestURL: hookDestURL(in: dir))

    let siblings = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    #expect(siblings.contains { $0.hasPrefix("settings.json.bak-") })
}

@Test func stateReflectsInstalledAndNotInstalled() throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let settings = settingsURL(in: dir)

    #expect(HookInstaller.state(settingsURL: settings) == .notInstalled)

    try HookInstaller.install(settingsURL: settings, hookDestURL: hookDestURL(in: dir))
    #expect(HookInstaller.state(settingsURL: settings) == .installed)

    try HookInstaller.uninstall(settingsURL: settings, hookDestURL: hookDestURL(in: dir))
    #expect(HookInstaller.state(settingsURL: settings) == .notInstalled)
}
