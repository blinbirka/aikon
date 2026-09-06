import Foundation

/// Installs and removes the Aikon session-state hook inside the running
/// app, so a person who only downloaded the .app (no repo, no scripts) can
/// turn it on from the app itself.
///
/// This is a Swift port of the old `scripts/hook/settings-patch.py` +
/// `scripts/install.sh` / `scripts/uninstall-hook.sh` combo. Behavior is
/// meant to match exactly: same events, same matchers, same command shape.
enum HookInstaller {

    // MARK: - What we register

    struct Registration: Equatable {
        let event: String
        let matcher: String?
        let arg: String
    }

    /// Which events fire the hook, which matcher (if any) narrows it, and
    /// which explicit marker argument the hook script gets so it never has
    /// to guess from free-form notification text. See
    /// `Sources/Aikon/Resources/hook/aikon-hook.sh` for what each arg does.
    ///
    /// `Notification`'s matcher values are documented at
    /// https://code.claude.com/docs/en/hooks.md — the event "matches on
    /// notification type" (permission_prompt, idle_prompt,
    /// agent_needs_input, ...), and `|` is valid alternation on a matcher
    /// for this event, so "idle_prompt|agent_needs_input" is one
    /// registration, not two. `PermissionRequest`, `Elicitation`, and
    /// `Stop` don't need a matcher: each already means exactly one thing.
    static let registrations: [Registration] = [
        Registration(event: "PermissionRequest", matcher: nil, arg: "permission"),
        Registration(event: "Notification", matcher: "permission_prompt", arg: "permission"),
        Registration(event: "Notification", matcher: "idle_prompt|agent_needs_input", arg: "answer"),
        Registration(event: "Elicitation", matcher: nil, arg: "answer"),
        Registration(event: "Stop", matcher: nil, arg: "done"),
    ]

    /// Substring that identifies a hooks[event] entry as ours among
    /// possibly many hooks a person already has registered.
    static let marker = "aikon-hook.sh"

    /// Path written into settings.json verbatim, unexpanded — it resolves
    /// at hook-run time, not at install time, the same way every other
    /// hook entry in that file already does.
    static let hookPathTemplate = "$HOME/.claude/aikon/aikon-hook.sh"

    static let settingsURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".claude/settings.json")

    static let installedHookURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".claude/aikon/aikon-hook.sh")

    // MARK: - Public state

    enum HookState: Equatable {
        case installed
        case notInstalled
        case unavailable(String)
    }

    enum InstallerError: LocalizedError {
        case bundleResourceMissing
        case settingsCorrupt(path: String, reason: String)
        case fileSystem(String)

        var errorDescription: String? {
            switch self {
            case .bundleResourceMissing:
                return L.string("hook.error.resourceMissing")
            case .settingsCorrupt(let path, let reason):
                return L.format("hook.error.settingsCorrupt", path, reason)
            case .fileSystem(let message):
                return L.format("hook.error.fileSystem", message)
            }
        }
    }

    /// Whether the hook is currently registered in `settingsURL`.
    /// `.unavailable` means we couldn't tell — settings.json exists but
    /// isn't valid JSON, for instance.
    static func state(settingsURL: URL = HookInstaller.settingsURL) -> HookState {
        do {
            guard let settings = try readSettings(at: settingsURL) else {
                return .notInstalled
            }
            return isFullyRegistered(in: settings) ? .installed : .notInstalled
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    /// Copies the bundled hook script to `~/.claude/aikon/aikon-hook.sh`
    /// and registers it in settings.json. Safe to call again later: it
    /// updates its own entries instead of duplicating them.
    static func install(settingsURL: URL = HookInstaller.settingsURL,
                         hookDestURL: URL = HookInstaller.installedHookURL,
                         hookPath: String = HookInstaller.hookPathTemplate) throws {
        try copyHookScriptIntoPlace(destination: hookDestURL)
        try patchSettings(at: settingsURL, createIfMissing: true) { settings in
            register(into: &settings, hookPath: hookPath)
        }
    }

    /// Removes our entries from settings.json and deletes the copied
    /// script. Leaves every other hook untouched. Safe to call when
    /// nothing is installed.
    static func uninstall(settingsURL: URL = HookInstaller.settingsURL,
                           hookDestURL: URL = HookInstaller.installedHookURL) throws {
        try patchSettings(at: settingsURL, createIfMissing: false) { settings in
            unregister(from: &settings)
        }
        if FileManager.default.fileExists(atPath: hookDestURL.path) {
            try FileManager.default.removeItem(at: hookDestURL)
        }
    }

    // MARK: - Bundled script

    private static func copyHookScriptIntoPlace(destination: URL) throws {
        // SwiftPM's .process() resource step flattens plain files straight
        // into the bundle root (unlike .lproj folders, which it keeps),
        // so the source directory `Resources/hook/` doesn't survive —
        // no `subdirectory:` here.
        guard let source = Bundle.module.url(forResource: "aikon-hook", withExtension: "sh") else {
            throw InstallerError.bundleResourceMissing
        }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: source, to: destination)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        } catch {
            throw InstallerError.fileSystem(error.localizedDescription)
        }
    }

    // MARK: - settings.json JSON model helpers (testable on any URL)

    /// Reads settings.json at `url`. `nil` means the file doesn't exist
    /// (not an error — the caller decides what "missing" means for it).
    /// Throws `.settingsCorrupt` if the file exists but isn't a JSON
    /// object, so callers never silently overwrite something unreadable.
    static func readSettings(at url: URL) throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw InstallerError.fileSystem(error.localizedDescription)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            throw InstallerError.settingsCorrupt(path: url.path, reason: "not a JSON object")
        }
        return dict
    }

    private static func writeSettings(_ settings: [String: Any], to url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        } catch {
            throw InstallerError.fileSystem(error.localizedDescription)
        }
    }

    /// Timestamped copy of settings.json made right before every write, so
    /// a bad patch is always recoverable by hand.
    private static func backup(_ url: URL) throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let destination = url.deletingLastPathComponent()
            .appending(path: url.lastPathComponent + ".bak-\(stamp)")
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
        } catch {
            throw InstallerError.fileSystem(error.localizedDescription)
        }
    }

    /// Reads (or starts empty), mutates, backs up the previous file if any
    /// existed, then writes. `createIfMissing` controls what happens when
    /// there's no settings.json yet: install wants one created, uninstall
    /// has nothing to do in that case.
    private static func patchSettings(at url: URL, createIfMissing: Bool,
                                       mutate: (inout [String: Any]) -> Void) throws {
        let fileExisted = FileManager.default.fileExists(atPath: url.path)
        guard fileExisted || createIfMissing else { return }

        var settings: [String: Any]
        if fileExisted {
            guard let existing = try readSettings(at: url) else {
                // fileExisted just told us it's there; readSettings only
                // returns nil for "doesn't exist", so this can't happen,
                // but fall back to empty rather than force-unwrap.
                settings = [:]
                mutate(&settings)
                try writeSettings(settings, to: url)
                return
            }
            settings = existing
        } else {
            settings = [:]
        }

        mutate(&settings)

        if fileExisted {
            try backup(url)
        }
        try writeSettings(settings, to: url)
    }

    // MARK: - Registration logic (ported from settings-patch.py)

    private static func isOurs(_ entry: [String: Any]) -> Bool {
        guard let commands = entry["hooks"] as? [[String: Any]], !commands.isEmpty else { return false }
        return commands.allSatisfy { ($0["command"] as? String)?.contains(marker) ?? false }
    }

    private static func matches(_ entry: [String: Any], _ registration: Registration) -> Bool {
        guard isOurs(entry) else { return false }
        return (entry["matcher"] as? String) == registration.matcher
    }

    private static func command(hookPath: String, arg: String) -> String {
        "bash \"\(hookPath)\" \(arg)"
    }

    private static func buildGroup(hookPath: String, registration: Registration) -> [String: Any] {
        var group: [String: Any] = [
            "hooks": [
                [
                    "type": "command",
                    "command": command(hookPath: hookPath, arg: registration.arg),
                    "timeout": 5,
                    "async": true,
                ] as [String: Any]
            ]
        ]
        if let matcher = registration.matcher {
            group["matcher"] = matcher
        }
        return group
    }

    private static func isFullyRegistered(in settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        for registration in registrations {
            guard let entries = hooks[registration.event] as? [[String: Any]],
                  entries.contains(where: { matches($0, registration) }) else {
                return false
            }
        }
        return true
    }

    /// Adds our entries, or updates them in place if already present —
    /// never appends a duplicate. Any other hook already in the same
    /// event's list is left exactly where it was.
    private static func register(into settings: inout [String: Any], hookPath: String) {
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for registration in registrations {
            var entries = hooks[registration.event] as? [[String: Any]] ?? []
            let group = buildGroup(hookPath: hookPath, registration: registration)
            if let index = entries.firstIndex(where: { matches($0, registration) }) {
                entries[index] = group
            } else {
                entries.append(group)
            }
            hooks[registration.event] = entries
        }
        settings["hooks"] = hooks
    }

    /// Removes our entries. Everything else in `hooks`, and every other
    /// top-level key in settings.json, stays untouched.
    private static func unregister(from settings: inout [String: Any]) {
        guard var hooks = settings["hooks"] as? [String: Any] else { return }
        for registration in registrations {
            guard var entries = hooks[registration.event] as? [[String: Any]] else { continue }
            entries.removeAll { matches($0, registration) }
            if entries.isEmpty {
                hooks.removeValue(forKey: registration.event)
            } else {
                hooks[registration.event] = entries
            }
        }
        settings["hooks"] = hooks
    }
}
