import Testing
import Foundation
@testable import Aikon

@Test func configRoundTripsThroughDisk() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "aikon-config-\(UUID())")
    let url = dir.appending(path: "config.json")
    defer { try? FileManager.default.removeItem(at: dir) }

    let written = AppConfig(
        version: 1,
        menuMode: .running,
        language: .ru,
        launchAtLogin: true,
        projects: [ProjectConfig(path: "/Users/example/Projects/alpha", name: "Alpha",
                                 emoji: "🚀", iconPath: "~/icons/alpha.png",
                                 pinned: true, hidden: false)])
    try written.write(to: url)

    let data = try Data(contentsOf: url)
    let read = try JSONDecoder().decode(AppConfig.self, from: data)
    #expect(read == written)
}

@Test func decodingToleratesMissingFields() throws {
    // An older config, or one hand-edited to drop a field.
    let json = """
    {"projects":[{"path":"/Users/example/Projects/beta","name":"Beta"}]}
    """
    let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(config.version == 1)
    #expect(config.menuMode == .pinned)
    #expect(config.language == .system)
    #expect(config.launchAtLogin == false)
    #expect(config.projects.first?.pinned == false)
    #expect(config.projects.first?.hidden == false)
    #expect(config.projects.first?.emoji == nil)
    #expect(config.projects.first?.iconPath == nil)
}

@Test func legacyShowAllVSCodeWindowsTrueBecomesPinnedMode() throws {
    // Old config, from before the field was renamed and its meaning
    // clarified — `true` used to mean "show every open VS Code window",
    // which `.pinned` now covers.
    let json = """
    {"showAllVSCodeWindows": true, "projects": []}
    """
    let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(config.menuMode == .pinned)
}

@Test func legacyShowAllVSCodeWindowsFalseBecomesRunningMode() throws {
    let json = """
    {"showAllVSCodeWindows": false, "projects": []}
    """
    let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(config.menuMode == .running)
}

@Test func menuModeRoundTripsThroughDisk() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "aikon-config-\(UUID())")
    let url = dir.appending(path: "config.json")
    defer { try? FileManager.default.removeItem(at: dir) }

    let written = AppConfig(menuMode: .running)
    try written.write(to: url)

    let data = try Data(contentsOf: url)
    let read = try JSONDecoder().decode(AppConfig.self, from: data)
    #expect(read.menuMode == .running)
    // and the legacy key isn't written back — only the new one
    let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(raw?["showAllVSCodeWindows"] == nil)
    #expect(raw?["menuMode"] as? String == "running")
}

@Test func bootstrapSeedsFromOpenAndSessionFolders() {
    let config = AppConfig.bootstrapped(
        openFolders: ["/Users/example/Projects/alpha"],
        sessionFolders: ["/Users/example/Projects/alpha", "/Users/example/Projects/beta"])
    // the duplicate (alpha, seen in both sources) is kept once, from the first source
    #expect(config.projects.map(\.path) == ["/Users/example/Projects/alpha",
                                             "/Users/example/Projects/beta"])
    #expect(config.projects.map(\.name) == ["alpha", "beta"])
}
