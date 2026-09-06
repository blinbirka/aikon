import Testing
@testable import Aikon
import Foundation

@Test @MainActor func doesNotJumpToAVanishedFolder() {
    // the folder was renamed or deleted while its window was open: `code`
    // would open an empty window on a path that no longer exists
    #expect(Opener.target(for: "/Users/example/Projects/no-such-folder-\(UUID())") == nil)
}

@Test @MainActor func fileInsteadOfFolderDoesNotQualify() {
    let file = FileManager.default.temporaryDirectory.appending(path: "panel-\(UUID()).txt")
    try? Data("x".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    #expect(Opener.target(for: file.path) == nil)
}

@Test @MainActor func existingFolderReturnsItsPath() {
    let dir = FileManager.default.temporaryDirectory
        .appending(path: "panel with space \(UUID())")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let target = Opener.target(for: dir.path)
    #expect(target != nil)
    #expect(target?.contains("panel with space") == true)
}

@Test @MainActor func tempFolderIsNotAProject() {
    // resolvingSymlinksInPath turns /private/tmp into /tmp — the filter must catch both
    #expect(ProjectPaths.isRealProject("/tmp/claude-501/-Users-example-Projects-alpha") == false)
    #expect(ProjectPaths.isRealProject("/private/tmp/claude-501/x") == false)
    #expect(ProjectPaths.isRealProject("/Users/example/Projects/alpha/scratchpad") == false)
    #expect(ProjectPaths.isRealProject("/Users/example/Projects/alpha") == true)
}
