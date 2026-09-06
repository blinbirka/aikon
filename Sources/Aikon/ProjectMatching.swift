import Foundation

/// A project as shown in the menu: a resolved name/emoji/icon for a folder,
/// whether or not that folder has an entry in the config.
struct Project: Equatable {
    let path: String
    let name: String
    let iconPath: String?

    /// An empty string in the config is the same thing as no emoji at all:
    /// the settings field starts out empty, and a row whose glyph is "" would
    /// render as a blank gap in the menu instead of falling back to the folder
    /// icon. Normalized here so no caller has to remember the difference.
    let emoji: String?

    init(path: String, name: String, emoji: String?, iconPath: String?) {
        self.path = path
        self.name = name
        self.iconPath = iconPath
        let trimmed = emoji?.trimmingCharacters(in: .whitespaces)
        self.emoji = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }
}

/// Turns the config's flat project list into what the menu needs: a lookup by
/// folder, the pinned group, and the idle (VS Code window without a Claude
/// Code session) group. Kept separate from PanelModel so it's testable without
/// touching the filesystem.
enum ProjectMatching {
    static let defaultEmoji = "📁"

    /// Canonicalizes a path so two spellings of the same folder compare equal:
    /// a trailing slash, or a symlink in the middle of it.
    ///
    /// This matters because the two sides being compared are canonicalized
    /// completely independently. `TranscriptIndex.cwd(ofTranscript:)` always
    /// resolves symlinks in what Claude Code wrote to the transcript, and
    /// `OpenWindows.folders()` does the same for VS Code's open windows — but
    /// `ProjectConfig.path` is whatever raw string the user's folder picker
    /// handed back when they added the project, never resolved. A project
    /// added while reachable through a symlink (the old `~/Desktop/Projects`
    /// shortcut was exactly this, see tmp/handoff-panel.md; an iCloud/Dropbox
    /// sync folder still is) would otherwise never match its own sessions —
    /// silently losing its name, emoji AND custom icon, since the row falls
    /// back to `project(at:)`'s "unconfigured folder" default — see
    /// `aProjectAddedThroughASymlinkStillMatchesItsSession` in
    /// `ProjectMatchingTests.swift`.
    ///
    /// `resolvingSymlinksInPath()` only resolves what actually exists on disk
    /// and otherwise just standardizes the string, so a renamed/deleted
    /// folder's config path degrades gracefully instead of crashing.
    static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    static func lookup(_ config: AppConfig) -> [String: ProjectConfig] {
        Dictionary(config.projects.map { (normalize($0.path), $0) }, uniquingKeysWith: { first, _ in first })
    }

    static func isHidden(_ path: String, config lookup: [String: ProjectConfig]) -> Bool {
        lookup[normalize(path)]?.hidden ?? false
    }

    /// The project configured for this exact folder, if any. nil means the
    /// folder isn't in the config at all — the caller falls back to the
    /// folder's own name.
    static func knownProject(at path: String, config lookup: [String: ProjectConfig]) -> Project? {
        guard let entry = lookup[normalize(path)] else { return nil }
        return Project(path: path, name: entry.name, emoji: entry.emoji, iconPath: entry.iconPath)
    }

    /// Same as `knownProject`, but always returns something: an unconfigured
    /// folder gets its own directory name and no emoji/icon.
    static func project(at path: String, config lookup: [String: ProjectConfig]) -> Project {
        knownProject(at: path, config: lookup) ??
            Project(path: path, name: URL(fileURLWithPath: path).lastPathComponent,
                    emoji: nil, iconPath: nil)
    }

    /// Pinned projects: shown in the order they appear in the config,
    /// regardless of whether anything is currently happening in them — but
    /// only in `.pinned` mode. In `.running` mode a pinned project with no
    /// session going isn't shown either; see `AppConfig.MenuMode`.
    static func pinnedProjects(_ config: AppConfig) -> [Project] {
        guard config.menuMode == .pinned else { return [] }
        return config.projects
            .filter { $0.pinned && !$0.hidden }
            .map { Project(path: $0.path, name: $0.name, emoji: $0.emoji, iconPath: $0.iconPath) }
    }

    /// Folders open in VS Code that don't already have a live Claude Code
    /// session row. In `.running` mode this list is always empty — a folder
    /// only shows up in the menu when there's a session.
    static func idleProjects(config: AppConfig, sessionPaths: Set<String>,
                              openFolders: Set<String>) -> [Project] {
        guard config.menuMode == .pinned else { return [] }
        let lookup = lookup(config)
        // Pinned folders already have their own group at the top of the menu,
        // so keep them out of this one instead of listing them twice.
        let pinned = Set(pinnedProjects(config).map(\.path))
        return openFolders
            .filter { !sessionPaths.contains($0) && !pinned.contains($0)
                      && !isHidden($0, config: lookup) }
            .map { project(at: $0, config: lookup) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
