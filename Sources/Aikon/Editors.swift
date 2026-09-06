import AppKit
import Foundation

/// One installed VS Code-family editor (VS Code itself, Cursor, Windsurf,
/// VSCodium, ...). Every fork ships a self-describing product.json, so Aikon
/// discovers editors instead of hardcoding a single app's bundle id or path —
/// that hardcoding used to mean the menu silently did nothing for anyone
/// whose editor wasn't stock VS Code at /Applications/Visual Studio Code.app.
struct Editor: Equatable {
    let appURL: URL
    let name: String
    let bundleID: String
    /// The CLI shim's filename in Contents/Resources/app/bin — "code" for VS
    /// Code, "cursor" for Cursor, etc.
    let cliName: String
    /// The scheme in "<scheme>://file/…" URLs, used when the CLI shim is
    /// missing or fails to launch.
    let urlScheme: String
    /// product.json's nameShort. Every fork also uses this as its folder
    /// name under ~/Library/Application Support, which is where its window
    /// state (storage.json) lives.
    let storageFolderName: String
}

extension Editor {
    /// Reads product.json and Info.plist straight off disk for one .app.
    static func from(appURL: URL) -> Editor? {
        let productData = try? Data(
            contentsOf: appURL.appending(path: "Contents/Resources/app/product.json"))
        let infoPlist = NSDictionary(
            contentsOf: appURL.appending(path: "Contents/Info.plist")) as? [String: Any]
        return parse(productJSON: productData, infoPlist: infoPlist, appURL: appURL)
    }

    /// Split out from `from(appURL:)` so tests can exercise the parsing logic
    /// with literal JSON/dictionaries instead of real .app bundles on disk.
    static func parse(productJSON: Data?, infoPlist: [String: Any]?, appURL: URL) -> Editor? {
        guard let productJSON,
              let root = try? JSONSerialization.jsonObject(with: productJSON) as? [String: Any]
        else { return nil }
        // applicationName is what every fork uses to name its CLI shim and
        // itself internally. An app with a product.json but no
        // applicationName isn't a VS Code fork — it's some other Electron app
        // that happens to ship a file with that name.
        guard let applicationName = root["applicationName"] as? String else { return nil }

        let name = (root["nameLong"] as? String)
            ?? appURL.deletingPathExtension().lastPathComponent
        let bundleID = (root["darwinBundleIdentifier"] as? String)
            ?? (infoPlist?["CFBundleIdentifier"] as? String)
            // Every real fork sets darwinBundleIdentifier; this only kicks in
            // for a hand-built product.json that's missing both.
            ?? applicationName
        let urlScheme = (root["urlProtocol"] as? String) ?? applicationName
        let storageFolderName = (root["nameShort"] as? String) ?? applicationName

        return Editor(appURL: appURL, name: name, bundleID: bundleID, cliName: applicationName,
                       urlScheme: urlScheme, storageFolderName: storageFolderName)
    }
}

@MainActor
extension Editor {
    /// /Applications and ~/Applications: the two places a .app can legally
    /// live. A missing directory (no per-user Applications folder exists on
    /// most Macs) just contributes nothing — it's not an error.
    static func searchDirectories() -> [URL] {
        [URL(fileURLWithPath: "/Applications"),
         FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications")]
    }

    /// Pure scan with no cache and no default directories, so tests can point
    /// it at a synthetic temp folder instead of the real /Applications.
    static func scan(directories: [URL]) -> [Editor] {
        let fm = FileManager.default
        var found: [Editor] = []
        for dir in directories {
            guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            else { continue }
            for appURL in contents where appURL.pathExtension == "app" {
                if let editor = Editor.from(appURL: appURL) { found.append(editor) }
            }
        }
        return found
    }

    private static var cache: (at: Date, editors: [Editor])?
    private static let ttl: TimeInterval = 300

    /// Discovering editors means listing two directories and reading a JSON
    /// file per .app — cheap once, but not worth doing on every 2-second menu
    /// refresh, matching the cache TTL style of ProjectPaths.knownPaths.
    static func discovered(now: Date = Date()) -> [Editor] {
        if let cache, now.timeIntervalSince(cache.at) < ttl { return cache.editors }
        let editors = scan(directories: searchDirectories())
        cache = (now, editors)
        return editors
    }

    /// Tests only: reset the five-minute cache.
    static func forgetCache() { cache = nil }

    /// Injectable so tests don't depend on which apps happen to be running on
    /// the machine executing them.
    static var isRunning: (String) -> Bool = { bundleID in
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Injectable so tests don't depend on real files under ~/Library.
    static var storageModificationDate: (Editor) -> Date? = { editor in
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/\(editor.storageFolderName)"
                       + "/User/globalStorage/storage.json")
        return (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate])
            as? Date
    }

    /// Which editor a click should open. Running beats "used most recently"
    /// beats alphabetical, so the choice never depends on directory
    /// traversal order — i.e. is never effectively random. Returns nil only
    /// when no VS Code-family editor is installed at all.
    static func preferred(among editors: [Editor] = discovered()) -> Editor? {
        guard !editors.isEmpty else { return nil }
        let byName = editors.sorted { $0.name < $1.name }

        if let running = byName.first(where: { isRunning($0.bundleID) }) { return running }

        let withDates = byName.compactMap { editor -> (Editor, Date)? in
            storageModificationDate(editor).map { (editor, $0) }
        }
        if let mostRecent = withDates.max(by: { $0.1 < $1.1 }) { return mostRecent.0 }

        return byName.first
    }
}
