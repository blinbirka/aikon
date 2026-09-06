import AppKit

@MainActor
enum Opener {
    static func reveal(path: String) {
        open(absolute: path)
    }

    static func revealProject(_ project: Project) {
        open(absolute: project.path)
    }

    /// `vscode://file/…` opened the folder as a new document — VS Code would open
    /// ANOTHER window even when the project was already open in one. The `code` CLI
    /// doesn't do that: it finds the window with that folder and switches to it.
    /// Verified against live windows.
    private static let codeCLI =
        "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"

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

        if FileManager.default.isExecutableFile(atPath: codeCLI) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: codeCLI)
            process.arguments = [path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            if (try? process.run()) != nil {
                bringVSCodeForward()
                return
            }
        }

        // fallback path, in case VS Code isn't installed where expected
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        guard let url = URL(string: "vscode://file/\(encoded)") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func bringVSCodeForward() {
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.microsoft.VSCode")
        running.first?.activate()
    }
}
