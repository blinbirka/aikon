import Testing
import Foundation
@testable import Aikon

@MainActor
private func tempConfigURL() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "aikon-store-\(UUID())/config.json")
}

@Test @MainActor func writesThenReadsBackTheSameConfig() {
    let url = tempConfigURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = ConfigStore(fileURL: url, openFolders: { [] }, sessionFolders: { [] })
    store.upsertProject(ProjectConfig(path: "/Users/example/Projects/alpha", name: "Alpha",
                                      emoji: "🚀", pinned: true))

    let reloaded = ConfigStore(fileURL: url, openFolders: { [] }, sessionFolders: { [] })
    #expect(reloaded.config.projects.count == 1)
    #expect(reloaded.config.projects.first?.name == "Alpha")
    #expect(reloaded.config.projects.first?.pinned == true)
}

@Test @MainActor func missingFileGivesDefaultsWithoutCrashing() {
    let url = tempConfigURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    // No open windows and no session folders to seed from — an empty machine.
    let store = ConfigStore(fileURL: url, openFolders: { [] }, sessionFolders: { [] })
    #expect(store.config == AppConfig())
}

@Test @MainActor func brokenJSONFallsBackToDefaultsAndLeavesTheFileAlone() throws {
    let url = tempConfigURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    let garbage = Data("{ this is not valid json".utf8)
    try garbage.write(to: url)

    let store = ConfigStore(fileURL: url, openFolders: { [] }, sessionFolders: { [] })
    #expect(store.config == AppConfig())
    #expect((try? Data(contentsOf: url)) == garbage)
}

@Test @MainActor func firstLaunchSeedsFromWhatsVisibleRightNow() {
    let url = tempConfigURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = ConfigStore(fileURL: url,
                            openFolders: { ["/Users/example/Projects/alpha"] },
                            sessionFolders: { ["/Users/example/Projects/beta"] })
    #expect(store.config.projects.map(\.name) == ["alpha", "beta"])
    // and it's saved, so the next launch doesn't re-scan
    #expect(FileManager.default.fileExists(atPath: url.path))
}

@Test @MainActor func menuModeWritesAndReadsBack() {
    let url = tempConfigURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = ConfigStore(fileURL: url, openFolders: { [] }, sessionFolders: { [] })
    store.setMenuMode(.running)
    #expect(store.config.menuMode == .running)

    let reloaded = ConfigStore(fileURL: url, openFolders: { [] }, sessionFolders: { [] })
    #expect(reloaded.config.menuMode == .running)
}

@Test @MainActor func pinnedTogglePersistsAcrossReload() {
    let url = tempConfigURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = ConfigStore(fileURL: url, openFolders: { [] }, sessionFolders: { [] })
    store.upsertProject(ProjectConfig(path: "/Users/example/Projects/alpha", name: "Alpha"))
    store.setPinned(path: "/Users/example/Projects/alpha", true)

    let reloaded = ConfigStore(fileURL: url, openFolders: { [] }, sessionFolders: { [] })
    #expect(reloaded.config.projects.first?.pinned == true)

    store.setPinned(path: "/Users/example/Projects/alpha", false)
    let reloadedAgain = ConfigStore(fileURL: url, openFolders: { [] }, sessionFolders: { [] })
    #expect(reloadedAgain.config.projects.first?.pinned == false)
}

@Test @MainActor func setHiddenAndSetPinnedUpdateTheMatchingProject() {
    let url = tempConfigURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = ConfigStore(fileURL: url, openFolders: { [] }, sessionFolders: { [] })
    store.upsertProject(ProjectConfig(path: "/Users/example/Projects/alpha", name: "Alpha"))

    store.setHidden(path: "/Users/example/Projects/alpha", true)
    #expect(store.config.projects.first?.hidden == true)

    store.setPinned(path: "/Users/example/Projects/alpha", true)
    #expect(store.config.projects.first?.pinned == true)

    store.removeProject(path: "/Users/example/Projects/alpha")
    #expect(store.config.projects.isEmpty)
}

@Test @MainActor func foundFoldersJoinTheListUnpinnedAndOnlyOnce() {
    let url = tempConfigURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = ConfigStore(fileURL: url, openFolders: { [] }, sessionFolders: { [] })
    store.upsertProject(ProjectConfig(path: "/Users/example/Projects/alpha", name: "Alpha", emoji: "🚀"))

    // Alpha is already there under another spelling; beta arrives twice.
    store.adoptFound(["/Users/example/Projects/alpha/",
                      "/Users/example/Projects/beta",
                      "/Users/example/Projects/beta"])

    #expect(store.config.projects.map(\.name) == ["Alpha", "beta"])
    #expect(store.config.projects.first?.emoji == "🚀")
    #expect(store.config.projects.allSatisfy { !$0.pinned && !$0.hidden })

    let reloaded = ConfigStore(fileURL: url, openFolders: { [] }, sessionFolders: { [] })
    #expect(reloaded.config.projects.map(\.name) == ["Alpha", "beta"])
}

@Test @MainActor func findingNothingNewDoesNotWriteTheFile() throws {
    let url = tempConfigURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = ConfigStore(fileURL: url, openFolders: { [] }, sessionFolders: { [] })
    store.adoptFound(["/Users/example/Projects/alpha"])
    try FileManager.default.removeItem(at: url)

    // The menu refreshes every two seconds; a write each time would be waste.
    store.adoptFound(["/Users/example/Projects/alpha"])
    #expect(!FileManager.default.fileExists(atPath: url.path))
}

@Test @MainActor func aRemovedProjectIsForgottenAndNotFoundAgain() {
    let url = tempConfigURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = ConfigStore(fileURL: url, openFolders: { [] }, sessionFolders: { [] })
    store.adoptFound(["/Users/example/Projects/alpha"])
    store.removeProject(path: "/Users/example/Projects/alpha")

    store.adoptFound(["/Users/example/Projects/alpha"])
    #expect(store.config.projects.isEmpty)

    let reloaded = ConfigStore(fileURL: url, openFolders: { [] }, sessionFolders: { [] })
    reloaded.adoptFound(["/Users/example/Projects/alpha"])
    #expect(reloaded.config.projects.isEmpty)
}

@Test @MainActor func addingAForgottenProjectByHandBringsItBack() {
    let url = tempConfigURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = ConfigStore(fileURL: url, openFolders: { [] }, sessionFolders: { [] })
    store.adoptFound(["/Users/example/Projects/alpha"])
    store.removeProject(path: "/Users/example/Projects/alpha")

    store.upsertProject(ProjectConfig(path: "/Users/example/Projects/alpha", name: "alpha"))
    #expect(store.config.projects.map(\.name) == ["alpha"])
    #expect(store.config.forgottenPaths.isEmpty)
}
