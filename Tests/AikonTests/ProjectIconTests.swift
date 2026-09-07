import Testing
@testable import Aikon
import AppKit

// `ProjectIcon.iconsDirectory` is a settable `static var` (the same
// injection pattern `TranscriptIndex.root` uses) so these tests can point it
// at a throwaway directory instead of the real `~/.config/aikon/icons`. Every
// test restores the real directory on the way out — see
// `withFakeIconsDirectory` — and no test reads or writes the real home
// directory.

@MainActor
private func withFakeIconsDirectory(_ body: (URL) throws -> Void) rethrows {
    let box = FileManager.default.temporaryDirectory.appendingPathComponent("aikon-icon-test-\(UUID())")
    let saved = ProjectIcon.iconsDirectory
    ProjectIcon.iconsDirectory = box
    defer {
        ProjectIcon.iconsDirectory = saved
        try? FileManager.default.removeItem(at: box)
    }
    try body(box)
}

/// A small in-memory image, rendered straight into an off-screen bitmap
/// context — no disk access and no window server needed.
private func makeTestImage(size: CGSize = CGSize(width: 4, height: 4)) -> NSImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor.red.setFill()
    NSRect(origin: .zero, size: size).fill()
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: size)
    image.addRepresentation(rep)
    return image
}

@Test @MainActor func saveWritesAPNGThatExistsOnDisk() throws {
    try withFakeIconsDirectory { _ in
        let path = try #require(ProjectIcon.save(makeTestImage()))
        #expect(FileManager.default.fileExists(atPath: path))
    }
}

@Test @MainActor func savedPathRoundTripsThroughImageFor() throws {
    try withFakeIconsDirectory { _ in
        let path = try #require(ProjectIcon.save(makeTestImage()))
        #expect(ProjectIcon.image(for: path) != nil)
    }
}

/// The source comment on `save` promises "every save gets a fresh name" so
/// `image(for:)` never sees a stale cache entry — this pins that contract.
@Test @MainActor func twoSavesOfTheSameImageReturnDifferentPaths() throws {
    try withFakeIconsDirectory { _ in
        let image = makeTestImage()
        let first = try #require(ProjectIcon.save(image))
        let second = try #require(ProjectIcon.save(image))
        #expect(first != second)
    }
}

@Test @MainActor func imageForReturnsNilForNil() {
    #expect(ProjectIcon.image(for: nil) == nil)
}

@Test @MainActor func imageForReturnsNilForAnEmptyString() {
    #expect(ProjectIcon.image(for: "") == nil)
}

@Test @MainActor func imageForReturnsNilForAPathThatDoesNotExist() throws {
    try withFakeIconsDirectory { box in
        let missing = box.appendingPathComponent("does-not-exist.png").path
        #expect(ProjectIcon.image(for: missing) == nil)
    }
}

// Tilde expansion (`image(for: "~/…")`) isn't covered here: `expandingTildeInPath`
// resolves through the real per-user home directory via directory services,
// not the `$HOME` environment variable — `setenv("HOME", …)` before calling it
// has no effect (verified directly: NSHomeDirectory() still returns the real
// home after overriding `$HOME`). There's no injection point for it the way
// `iconsDirectory` is injectable for `save`, so exercising it would mean
// reading or writing under the real home directory, which the task rules out.

/// When the directory can't be created — here because a path component on
/// the way to it is a regular file, not a folder — `save` reports failure
/// instead of crashing.
@Test @MainActor func saveReturnsNilWhenTheDestinationDirectoryCannotBeCreated() throws {
    let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("aikon-icon-blocker-\(UUID())")
    try Data("not a directory".utf8).write(to: blocker)
    let saved = ProjectIcon.iconsDirectory
    ProjectIcon.iconsDirectory = blocker.appendingPathComponent("icons")
    defer {
        ProjectIcon.iconsDirectory = saved
        try? FileManager.default.removeItem(at: blocker)
    }

    #expect(ProjectIcon.save(makeTestImage()) == nil)
}
