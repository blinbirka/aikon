import Testing
import Foundation
@testable import Aikon

private func config(_ projects: [ProjectConfig], menuMode: MenuMode = .pinned) -> AppConfig {
    AppConfig(menuMode: menuMode, projects: projects)
}

@Test func hiddenProjectIsExcludedFromTheIdleList() {
    let cfg = config([
        ProjectConfig(path: "/Users/example/Projects/alpha", name: "Alpha", hidden: true),
        ProjectConfig(path: "/Users/example/Projects/beta", name: "Beta")
    ])
    let idle = ProjectMatching.idleProjects(
        config: cfg, sessionPaths: [],
        openFolders: ["/Users/example/Projects/alpha", "/Users/example/Projects/beta"])
    #expect(idle.map(\.name) == ["Beta"])
}

@Test func pinnedProjectsFormTheirOwnGroupInConfigOrder() {
    let cfg = config([
        ProjectConfig(path: "/Users/example/Projects/beta", name: "Beta", pinned: true),
        ProjectConfig(path: "/Users/example/Projects/alpha", name: "Alpha", pinned: true),
        ProjectConfig(path: "/Users/example/Projects/gamma", name: "Gamma", pinned: false)
    ])
    let pinned = ProjectMatching.pinnedProjects(cfg)
    // config order, not alphabetical — Beta then Alpha
    #expect(pinned.map(\.name) == ["Beta", "Alpha"])
}

@Test func hiddenPinnedProjectDoesNotShowUpEither() {
    let cfg = config([
        ProjectConfig(path: "/Users/example/Projects/alpha", name: "Alpha", pinned: true, hidden: true)
    ])
    #expect(ProjectMatching.pinnedProjects(cfg).isEmpty)
}

@Test func pinnedModeRevealsAFolderWithoutASession() {
    let cfg = config([], menuMode: .pinned)
    let idle = ProjectMatching.idleProjects(
        config: cfg, sessionPaths: [], openFolders: ["/Users/example/Projects/alpha"])
    #expect(idle.map(\.path) == ["/Users/example/Projects/alpha"])
}

@Test func runningModeHidesAFolderWithoutASession() {
    let cfg = config([], menuMode: .running)
    let idle = ProjectMatching.idleProjects(
        config: cfg, sessionPaths: [], openFolders: ["/Users/example/Projects/alpha"])
    #expect(idle.isEmpty)
}

@Test func aFolderAlreadyShownAsASessionIsNotAlsoListedAsIdle() {
    let cfg = config([], menuMode: .pinned)
    let idle = ProjectMatching.idleProjects(
        config: cfg, sessionPaths: ["/Users/example/Projects/alpha"],
        openFolders: ["/Users/example/Projects/alpha"])
    #expect(idle.isEmpty)
}

@Test func runningModeExcludesAPinnedProjectWithNoSession() {
    let cfg = config([
        ProjectConfig(path: "/Users/example/Projects/alpha", name: "Alpha", pinned: true)
    ], menuMode: .running)
    #expect(ProjectMatching.pinnedProjects(cfg).isEmpty)
}

@Test func pinnedModeIncludesAPinnedProjectWithNoSession() {
    let cfg = config([
        ProjectConfig(path: "/Users/example/Projects/alpha", name: "Alpha", pinned: true)
    ], menuMode: .pinned)
    #expect(ProjectMatching.pinnedProjects(cfg).map(\.name) == ["Alpha"])
}

@Test func projectNameNotInConfigFallsBackToTheFolderName() {
    let cfg = config([])
    let project = ProjectMatching.project(at: "/Users/example/Projects/alpha",
                                          config: ProjectMatching.lookup(cfg))
    #expect(project.name == "alpha")
    #expect(project.emoji == nil)
}

@Test func knownProjectIsNilWhenTheFolderIsNotInTheConfig() {
    #expect(ProjectMatching.knownProject(at: "/Users/example/Projects/alpha", config: [:]) == nil)
}

@Test func knownProjectUsesTheConfiguredNameAndEmoji() {
    let cfg = config([ProjectConfig(path: "/Users/example/Projects/alpha", name: "Alpha", emoji: "🚀")])
    let project = ProjectMatching.knownProject(at: "/Users/example/Projects/alpha",
                                               config: ProjectMatching.lookup(cfg))
    #expect(project?.name == "Alpha")
    #expect(project?.emoji == "🚀")
}

/// A project added while reachable through a symlink (the old
/// `~/Desktop/Projects` shortcut was exactly this — see
/// tmp/handoff-panel.md — and an iCloud/Dropbox sync folder still is) used
/// to never match its own sessions: `TranscriptIndex.cwd(ofTranscript:)`
/// resolves symlinks in what Claude Code wrote to the transcript, but the
/// config path — whatever raw string the folder picker handed back — never
/// was. The row fell back to `project(at:)`'s "unconfigured folder" default:
/// no name, no emoji, no custom icon, even though the project WAS configured.
@Test func aProjectAddedThroughASymlinkStillMatchesItsSession() throws {
    let base = FileManager.default.temporaryDirectory
        .appending(path: "aikon-symlink-match-\(UUID().uuidString)")
    let real = base.appending(path: "real_project")
    let link = base.appending(path: "link_project")
    try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
    defer { try? FileManager.default.removeItem(at: base) }

    // The config holds the path exactly as the user's folder picker returned
    // it: through the symlink, unresolved.
    let cfg = config([ProjectConfig(path: link.path, name: "Repro", emoji: "🔥",
                                    iconPath: "~/icon.png")])
    let lookup = ProjectMatching.lookup(cfg)

    // The session's cwd, as TranscriptIndex.cwd(ofTranscript:) would hand it
    // to PanelModel.refresh() — already canonicalized.
    let resolvedSessionPath = link.resolvingSymlinksInPath().path
    #expect(resolvedSessionPath == real.path)   // sanity: the symlink really is resolved

    let matched = try #require(ProjectMatching.knownProject(at: resolvedSessionPath, config: lookup))
    #expect(matched.name == "Repro")
    #expect(matched.emoji == "🔥")
    #expect(matched.iconPath == "~/icon.png")
}

/// A project saved with an empty emoji field used to render as a blank gap in
/// the menu: `?? defaultEmoji` only catches nil, never an empty string.
@Test func anEmptyEmojiCountsAsNoEmoji() {
    #expect(Project(path: "/tmp/a", name: "A", emoji: "", iconPath: nil).emoji == nil)
    #expect(Project(path: "/tmp/a", name: "A", emoji: "   ", iconPath: nil).emoji == nil)
    #expect(Project(path: "/tmp/a", name: "A", emoji: "🚀", iconPath: nil).emoji == "🚀")
}
