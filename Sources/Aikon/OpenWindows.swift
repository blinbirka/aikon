import AppKit

/// Which folders are open in VS Code right now.
///
/// Without this, the panel would only show sessions that wrote to their transcript
/// in the last half hour: several windows could be open while the menu still showed
/// just one. An open window is a far more honest signal of "this project is in
/// progress" than how recently its file was touched.
@MainActor
enum OpenWindows {
    /// Each VS Code-family editor keeps its window state under its own
    /// nameShort folder, so the path can only be known once we've picked
    /// which editor is in use.
    private static func storage(for editor: Editor) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/\(editor.storageFolderName)"
                       + "/User/globalStorage/storage.json")
    }

    /// canonical path → the path the folder is ACTUALLY OPEN with in the editor.
    /// These differ when a symlink points at the real folder: Claude Code and
    /// the editor can each remember a different variant of the same folder.
    private static var cache: (at: Date, byCanonical: [String: String])?
    private static let ttl: TimeInterval = 10

    /// storage.json stays on disk after the editor quits and keeps listing
    /// windows that no longer exist. Without this check, a closed editor
    /// would keep sessions in the menu for a full day.
    static var isVSCodeRunning: () -> Bool = {
        guard let editor = Editor.preferred() else { return false }
        return !NSRunningApplication.runningApplications(
            withBundleIdentifier: editor.bundleID).isEmpty
    }

    /// The last successfully parsed list. VS Code rewrites storage.json in full,
    /// and at that moment the file reads as broken — the menu shouldn't be reset
    /// because of that, or rows would flicker.
    private static var lastGood: [String: String] = [:]

    /// Parses storage.json. nil means the file can't be read or isn't the right JSON.
    static func parse(_ data: Data) -> [String: String]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = root["windowsState"] as? [String: Any] else { return nil }

        var windows: [[String: Any]] = []
        if let last = state["lastActiveWindow"] as? [String: Any] { windows.append(last) }
        if let opened = state["openedWindows"] as? [[String: Any]] { windows += opened }

        var found: [String: String] = [:]
        for window in windows {
            guard let raw = window["folder"] as? String,
                  let url = URL(string: raw), url.isFileURL else { continue }
            let canonical = url.resolvingSymlinksInPath().path
            // A folder can be open both directly and through a symlink. Prefer the
            // variant that matches the real path: that's the one Claude Code
            // records in the session.
            if found[canonical] == nil || url.path == canonical {
                found[canonical] = url.path
            }
        }
        return found
    }

    /// Tests only: reset the ten-second cache.
    static func forgetCache() { cache = nil; lastGood = [:] }

    static func folders() -> Set<String> {
        Set(map().keys)
    }

    /// Which path to use to open the folder so VS Code switches to the existing
    /// window instead of opening a second one. If there's no window, the path
    /// stays as is.
    static func pathAsOpened(_ canonical: String) -> String {
        map()[canonical] ?? canonical
    }

    private static func map() -> [String: String] {
        if let cache, Date().timeIntervalSince(cache.at) < ttl { return cache.byCanonical }

        var found: [String: String] = [:]
        if isVSCodeRunning(), let editor = Editor.preferred() {
            if let data = try? Data(contentsOf: storage(for: editor)), let parsed = parse(data) {
                found = parsed
                lastGood = parsed
            } else {
                found = lastGood
            }
        } else {
            lastGood = [:]
        }

        cache = (Date(), found)
        return found
    }
}
