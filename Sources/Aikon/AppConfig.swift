import Foundation

/// One project the user told the app about: display name, optional emoji or
/// custom icon, and whether it's pinned or hidden. `path` is the folder it
/// points at.
struct ProjectConfig: Codable, Equatable {
    var path: String
    var name: String
    var emoji: String?
    var iconPath: String?
    var pinned: Bool
    var hidden: Bool

    init(path: String, name: String, emoji: String? = nil, iconPath: String? = nil,
         pinned: Bool = false, hidden: Bool = false) {
        self.path = path
        self.name = name
        self.emoji = emoji
        self.iconPath = iconPath
        self.pinned = pinned
        self.hidden = hidden
    }

    private enum CodingKeys: String, CodingKey {
        case path, name, emoji, iconPath, pinned, hidden
    }

    // Custom decoding so an older config that's missing a field (e.g. a config
    // written before `hidden` existed) still loads instead of failing outright.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        name = try c.decode(String.self, forKey: .name)
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji)
        iconPath = try c.decodeIfPresent(String.self, forKey: .iconPath)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
    }
}

/// Decodes one `projects` array element leniently: a malformed entry (e.g.
/// missing `path`/`name`, or one with an empty `path`/`name`) becomes `nil`
/// instead of failing the whole array, so one bad line in a hand-edited
/// config can't wipe out every other project.
private struct LossyProjectConfig: Decodable {
    let project: ProjectConfig?

    init(from decoder: Decoder) throws {
        if let value = try? ProjectConfig(from: decoder), !value.path.isEmpty, !value.name.isEmpty {
            project = value
        } else {
            project = nil
        }
    }
}

enum AppLanguage: String, Codable {
    case system, en, ru
}

/// What shows up in the menu bar dropdown when nothing is happening in a
/// project. `.pinned` keeps every pinned project visible (plus whatever has
/// a session going); `.running` shows only projects with a session going.
enum MenuMode: String, Codable {
    case pinned, running
}

/// Everything that used to be hardcoded for one person now lives here, on
/// disk, at `~/.config/aikon/config.json`.
struct AppConfig: Codable, Equatable {
    var version: Int
    var menuMode: MenuMode
    var language: AppLanguage
    var launchAtLogin: Bool
    /// Where Claude Code writes session transcripts. Unexpanded (`~` kept
    /// literal), same convention as `ProjectConfig.iconPath` — expanded only
    /// at the point of use.
    var sessionsPath: String
    var projects: [ProjectConfig]
    /// Up to eight most-recently-chosen emoji, most recent first, shared
    /// across every project — what the icon picker's "Recent" row shows.
    var recentEmojis: [String]
    /// Master switch for `UpdateChecker`. Off means no network request is
    /// ever made — not "made and ignored", never sent.
    var checkForUpdates: Bool
    /// When `UpdateChecker` last asked GitHub, successfully or not — the
    /// input to "not more than once a day". `nil` means it hasn't checked yet.
    var lastUpdateCheckAt: Date?
    /// The newest tag_name a successful check has seen, "v" stripped
    /// (e.g. "0.2.0"). Kept even when it's not newer than `AppVersion.current`
    /// — it's just the last thing GitHub reported, not a "there's an update"
    /// flag; that comparison happens where it's displayed.
    var latestKnownVersion: String?
    /// Folders removed from the Projects list by hand. `ConfigStore.adoptFound`
    /// adds whatever the menu finds, and without this a removed project would
    /// be back on the next refresh. Adding one by hand takes it off again.
    var forgottenPaths: [String]

    static let defaultSessionsPath = "~/.claude/projects"

    init(version: Int = 1,
         menuMode: MenuMode = .pinned,
         language: AppLanguage = .system,
         launchAtLogin: Bool = false,
         sessionsPath: String = AppConfig.defaultSessionsPath,
         projects: [ProjectConfig] = [],
         recentEmojis: [String] = [],
         checkForUpdates: Bool = true,
         lastUpdateCheckAt: Date? = nil,
         latestKnownVersion: String? = nil,
         forgottenPaths: [String] = []) {
        self.version = version
        self.menuMode = menuMode
        self.language = language
        self.launchAtLogin = launchAtLogin
        self.sessionsPath = sessionsPath
        self.projects = projects
        self.recentEmojis = recentEmojis
        self.checkForUpdates = checkForUpdates
        self.lastUpdateCheckAt = lastUpdateCheckAt
        self.latestKnownVersion = latestKnownVersion
        self.forgottenPaths = forgottenPaths
    }

    private enum CodingKeys: String, CodingKey {
        // `showAllVSCodeWindows` isn't a stored property anymore — it's only
        // here so decoding can still find it in a config written by an
        // older version of the app (see `init(from:)` below).
        case version, menuMode, showAllVSCodeWindows, language, launchAtLogin, sessionsPath, projects, recentEmojis,
             checkForUpdates, lastUpdateCheckAt, latestKnownVersion, forgottenPaths
    }

    // Every field falls back to its default when missing, so a config file
    // from an older version of the app — or one hand-edited to drop a field —
    // still loads instead of being treated as broken.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        if let mode = try c.decodeIfPresent(MenuMode.self, forKey: .menuMode) {
            menuMode = mode
        } else if let legacyShowAll = try c.decodeIfPresent(Bool.self, forKey: .showAllVSCodeWindows) {
            // Old field, renamed because its meaning changed: it used to mean
            // "show every open VS Code window"; now `.pinned` means "keep
            // pinned projects visible". `true` mapped to the old all-windows
            // behavior, which is what `.pinned` replaces, so that's the
            // faithful migration for someone's existing setting.
            menuMode = legacyShowAll ? .pinned : .running
        } else {
            menuMode = .pinned
        }
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        sessionsPath = try c.decodeIfPresent(String.self, forKey: .sessionsPath) ?? AppConfig.defaultSessionsPath
        // Decoded leniently, per element: one malformed entry — or `projects`
        // being an unexpected shape entirely, e.g. a string — falls back to
        // dropping just that entry (or all of them) rather than throwing and
        // losing the rest of the config.
        if let lossy = try? c.decodeIfPresent([LossyProjectConfig].self, forKey: .projects) {
            projects = lossy.compactMap(\.project)
        } else {
            projects = []
        }
        recentEmojis = try c.decodeIfPresent([String].self, forKey: .recentEmojis) ?? []
        checkForUpdates = try c.decodeIfPresent(Bool.self, forKey: .checkForUpdates) ?? true
        lastUpdateCheckAt = try c.decodeIfPresent(Date.self, forKey: .lastUpdateCheckAt)
        latestKnownVersion = try c.decodeIfPresent(String.self, forKey: .latestKnownVersion)
        forgottenPaths = try c.decodeIfPresent([String].self, forKey: .forgottenPaths) ?? []
    }

    // Written by hand (rather than relying on synthesis) because
    // `CodingKeys` carries the legacy `showAllVSCodeWindows` case, which has
    // no matching stored property — synthesis needs every case to map to one.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(menuMode, forKey: .menuMode)
        try c.encode(language, forKey: .language)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
        try c.encode(sessionsPath, forKey: .sessionsPath)
        try c.encode(projects, forKey: .projects)
        try c.encode(recentEmojis, forKey: .recentEmojis)
        try c.encode(checkForUpdates, forKey: .checkForUpdates)
        try c.encodeIfPresent(lastUpdateCheckAt, forKey: .lastUpdateCheckAt)
        try c.encodeIfPresent(latestKnownVersion, forKey: .latestKnownVersion)
        try c.encode(forgottenPaths, forKey: .forgottenPaths)
    }

    /// First launch, no config file yet: seed one from what's actually visible
    /// right now instead of leaving the menu empty. Order: currently open VS
    /// Code windows first, then folders known from Claude Code sessions;
    /// duplicates are dropped, keeping the first occurrence.
    static func bootstrapped(openFolders: [String], sessionFolders: [String]) -> AppConfig {
        var seen = Set<String>()
        var projects: [ProjectConfig] = []
        for path in openFolders + sessionFolders {
            guard seen.insert(path).inserted else { continue }
            projects.append(ProjectConfig(path: path,
                                          name: URL(fileURLWithPath: path).lastPathComponent))
        }
        return AppConfig(projects: projects)
    }

    /// Atomic write: encode to a temp file in the same directory, then swap it
    /// into place, so a crash or a concurrent read never sees a half-written file.
    func write(to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)

        let tmp = dir.appending(path: "config-\(UUID().uuidString).tmp")
        try data.write(to: tmp, options: .atomic)
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            // replaceItemAt can refuse when the destination doesn't exist yet
            // on some filesystems — fall back to a plain move in that case.
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: tmp, to: url)
        }
    }
}
