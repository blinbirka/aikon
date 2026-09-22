import AppKit

/// Custom project icon: a PNG the user picked in settings, addressed by a
/// path on disk (`~` is expanded). A project without an icon path falls back
/// to its emoji, and to a folder icon if that's missing too — that fallback
/// lives in MenuView, not here.
@MainActor
enum ProjectIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(for iconPath: String?) -> NSImage? {
        guard let iconPath, !iconPath.isEmpty else { return nil }
        let expanded = (iconPath as NSString).expandingTildeInPath
        if let hit = cache[expanded] { return hit }
        guard let image = NSImage(contentsOfFile: expanded) else { return nil }
        cache[expanded] = image
        return image
    }

    /// A `var` (not `let`) so tests can point it at a temp directory instead
    /// of the real `~/.config/aikon/icons` — same injection pattern as
    /// `TranscriptIndex.root`.
    static var iconsDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".config/aikon/icons")

    /// Saves an image dropped or pasted onto a project's icon well as a PNG
    /// under `~/.config/aikon/icons` and returns the path to store in
    /// `ProjectConfig.iconPath`. Unlike a file picked via `NSOpenPanel`
    /// (which already has a stable path of its own), a dropped or pasted
    /// image only exists in memory, so it needs somewhere to live. Every
    /// save gets a fresh name, so there's never a stale cache entry for
    /// `image(for:)` to worry about.
    static func save(_ image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return nil }
        do {
            try FileManager.default.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)
            let url = iconsDirectory.appending(path: "\(UUID().uuidString).png")
            try data.write(to: url)
            return url.path
        } catch {
            return nil
        }
    }

    /// Copies a picture the user picked into `directory` and returns the
    /// copy's path. The original may sit in Downloads or on the Desktop and
    /// get moved or deleted later — storing its own path is how logos used
    /// to vanish.
    static func importFile(at source: URL, into directory: URL = iconsDirectory) -> String? {
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: "\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: source, to: url)
            return url.path
        } catch {
            FileHandle.standardError.write(
                Data("aikon: couldn't copy icon \(source.path): \(error)\n".utf8))
            return nil
        }
    }
}
