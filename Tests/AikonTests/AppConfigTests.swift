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
                                 pinned: true, hidden: false)],
        forgottenPaths: ["/Users/example/Projects/old"])
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
    #expect(config.forgottenPaths.isEmpty)
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

@Test func oneMalformedProjectEntryDoesNotWipeTheOthers() throws {
    // Three good entries, one bad one (missing `name`) mixed in. The bad
    // entry is dropped; the three good ones still load.
    let json = """
    {"projects":[
        {"path":"/Users/example/Projects/alpha","name":"Alpha"},
        {"path":"/Users/example/Projects/broken"},
        {"path":"/Users/example/Projects/beta","name":"Beta"},
        {"path":"/Users/example/Projects/gamma","name":"Gamma"}
    ]}
    """
    let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(config.projects.map(\.name) == ["Alpha", "Beta", "Gamma"])
}

@Test func projectEntryWithEmptyPathIsDropped() throws {
    let json = """
    {"projects":[
        {"path":"","name":"Empty path"},
        {"path":"/Users/example/Projects/beta","name":"Beta"}
    ]}
    """
    let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(config.projects.map(\.name) == ["Beta"])
}

@Test func completelyBrokenProjectsValueYieldsNoProjectsInsteadOfThrowing() throws {
    // `projects` here is a string, not an array — the rest of the config
    // must still decode instead of the whole thing throwing.
    let json = """
    {"version": 1, "projects": "not an array"}
    """
    let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(config.projects.isEmpty)
    #expect(config.version == 1)
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
