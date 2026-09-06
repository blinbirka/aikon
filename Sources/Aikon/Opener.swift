import AppKit

@MainActor
enum Opener {
    static func reveal(path: String) {
        open(absolute: path)
    }

    static func revealProject(_ project: Project) {
        open(absolute: project.path)
    }

    /// Which path to use to call VS Code. nil means the folder is no longer on
    /// disk: it could have been renamed or deleted while the window was open, and
    /// in that case `code` would open an empty window at a nonexistent path
    /// instead of switching to it.
    static func target(for path: String) -> String? {
        let canonical = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonical, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        // VS Code treats a symlink and its target as different folders, so the
        // window must be called with exactly the path it's open with, or a second
        // one will open.
        return OpenWindows.pathAsOpened(canonical)
    }

    private static func open(absolute path: String) {
        guard let path = target(for: path) else {
            FileHandle.standardError.write(
                Data("panel: folder \(path) no longer exists, navigation canceled\n".utf8))
            return
        }

        guard let editor = Editor.preferred() else {
            // Nothing to hand the folder to. Opening it in Finder means the
            // click still does something visible instead of silently nothing.
            FileHandle.standardError.write(
                Data("panel: no VS Code-family editor installed, opening \(path) in Finder\n"
                    .utf8))
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            return
        }

        // `<scheme>://file/…` opens the folder as a new document — the editor
        // would open ANOTHER window even when the project was already open in
        // one. The CLI shim doesn't do that: it finds the window with that
        // folder and switches to it. Verified against live windows.
        let cli = editor.appURL.appending(path: "Contents/Resources/app/bin/\(editor.cliName)")
        if FileManager.default.isExecutableFile(atPath: cli.path) {
            let process = Process()
            process.executableURL = cli
            process.arguments = [path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            if (try? process.run()) != nil {
                bringForward(editor)
                return
            }
        }

        // fallback path, in case the CLI shim is missing or fails to launch
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        guard let url = URL(string: "\(editor.urlScheme)://file/\(encoded)") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func bringForward(_ editor: Editor) {
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: editor.bundleID)
        running.first?.activate()
    }
}
