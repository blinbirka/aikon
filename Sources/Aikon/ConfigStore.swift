import Foundation

/// Holds the user's config in memory and keeps it in sync with
/// `~/.config/aikon/config.json`. A settings window (a separate task) would
/// read and write through this object.
@MainActor
final class ConfigStore: ObservableObject {
    /// Every path that changes the config runs through this property, so it's
    /// the one place that has to tell `L` which language to serve. Without it
    /// the picker in settings writes the choice to disk and nothing else
    /// happens — see `LocalizationTests`.
    @Published private(set) var config: AppConfig {
        didSet { L.language = config.language }
    }
    /// True when the file exists but couldn't be parsed. The Projects tab
    /// shows a dedicated error state for this instead of pretending
    /// everything's fine — see `load()`.
    @Published private(set) var loadFailed = false

    static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".config/aikon/config.json")

    private let fileURL: URL
    // Injectable so tests never touch the real VS Code storage or ~/.claude.
    private let openFolders: () -> [String]
    private let sessionFolders: () -> [String]

    init(fileURL: URL = ConfigStore.defaultURL,
         openFolders: @escaping () -> [String] = { Array(OpenWindows.folders()) },
         sessionFolders: @escaping () -> [String] = { ProjectPaths.knownPaths() }) {
        self.fileURL = fileURL
        self.openFolders = openFolders
        self.sessionFolders = sessionFolders
        self.config = AppConfig()
        load()
    }

    /// Re-reads the file. Meant to be called on the panel's existing refresh
    /// timer — simpler and more reliable than watching the file descriptor,
    /// since an atomic write (temp file + rename) swaps in a new inode that a
    /// `DispatchSource` opened on the old file would never see fire again.
    func load() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            let seeded = AppConfig.bootstrapped(openFolders: openFolders(), sessionFolders: sessionFolders())
            config = seeded
            save(seeded)
            loadFailed = false
            return
        }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            // Broken or unreadable: don't touch the file, and don't wipe out
            // whatever config is already in memory — just keep working.
            loadFailed = true
            return
        }
        config = decoded
        loadFailed = false
    }

    func save() { save(config) }

    private func save(_ config: AppConfig) {
        do {
            try config.write(to: fileURL)
        } catch {
            FileHandle.standardError.write(
                Data("aikon: couldn't save config: \(error)\n".utf8))
        }
    }

    func setMenuMode(_ value: MenuMode) {
        var updated = config
        updated.menuMode = value
        config = updated
        save()
    }

    func setLanguage(_ value: AppLanguage) {
        var updated = config
        updated.language = value
        config = updated
        save()
    }

    func setLaunchAtLogin(_ value: Bool) {
        var updated = config
        updated.launchAtLogin = value
        config = updated
        save()
    }

    func setSessionsPath(_ value: String) {
        var updated = config
        updated.sessionsPath = value
        config = updated
        save()
    }

    func setCheckForUpdates(_ value: Bool) {
        var updated = config
        updated.checkForUpdates = value
        config = updated
        save()
    }

    /// Called after every attempt (successful or not) so "once a day"
    /// keeps counting even when GitHub couldn't be reached. `latestVersion`
    /// is `nil` on a failed attempt — the previously known version, if any,
    /// is left untouched rather than wiped.
    func recordUpdateCheck(at date: Date, latestVersion: String?) {
        var updated = config
        updated.lastUpdateCheckAt = date
        if let latestVersion {
            updated.latestKnownVersion = latestVersion
        }
        config = updated
        save()
    }

    func setPinned(path: String, _ pinned: Bool) {
        updateProject(path: path) { $0.pinned = pinned }
    }

    func setHidden(path: String, _ hidden: Bool) {
        updateProject(path: path) { $0.hidden = hidden }
    }

    func upsertProject(_ project: ProjectConfig) {
        var updated = config
        if let index = updated.projects.firstIndex(where: { $0.path == project.path }) {
            updated.projects[index] = project
        } else {
            updated.projects.append(project)
        }
        config = updated
        save()
    }

    /// Moves `emoji` to the front of the shared "Recent" row (see
    /// `EmojiCatalog.updatingRecents`), adding it if it's new and dropping
    /// the oldest once there are more than eight.
    func recordRecentEmoji(_ emoji: String) {
        var updated = config
        updated.recentEmojis = EmojiCatalog.updatingRecents(updated.recentEmojis, adding: emoji)
        config = updated
        save()
    }

    func removeProject(path: String) {
        var updated = config
        updated.projects.removeAll { $0.path == path }
        config = updated
        save()
    }

    private func updateProject(path: String, _ mutate: (inout ProjectConfig) -> Void) {
        var updated = config
        guard let index = updated.projects.firstIndex(where: { $0.path == path }) else { return }
        mutate(&updated.projects[index])
        config = updated
        save()
    }
}
