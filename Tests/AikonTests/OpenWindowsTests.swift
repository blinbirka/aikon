import Testing
@testable import Aikon
import Foundation

@Test @MainActor func parsesVSCodeWindowList() {
    let json = """
    {"windowsState":{"lastActiveWindow":{"folder":"file:///Users/example/Projects/alpha"},
     "openedWindows":[{"folder":"file:///Users/example/Library/Mobile%20Documents/x/Demo%20Project"},
                      {"backupPath":"/tmp/nope"}]}}
    """
    let map = OpenWindows.parse(Data(json.utf8))
    #expect(map?.count == 2)
    // spaces in the path arrive percent-encoded and must be decoded
    #expect(map?["/Users/example/Library/Mobile Documents/x/Demo Project"]
            == "/Users/example/Library/Mobile Documents/x/Demo Project")
}

@Test @MainActor func brokenStorageJsonIsNoWindowList() {
    // VS Code rewrites the file wholesale: at that moment it reads truncated
    #expect(OpenWindows.parse(Data(#"{"windowsState":"#.utf8)) == nil)
    #expect(OpenWindows.parse(Data("not json at all".utf8)) == nil)
    // valid json without the needed section is not a list either
    #expect(OpenWindows.parse(Data(#"{"other":1}"#.utf8)) == nil)
}

@Test @MainActor func closedVSCodeMeansNoWindows() {
    let saved = OpenWindows.isVSCodeRunning
    defer { OpenWindows.isVSCodeRunning = saved }
    OpenWindows.isVSCodeRunning = { false }
    OpenWindows.forgetCache()
    #expect(OpenWindows.folders().isEmpty)
    // and the path to jump to stays whatever was given
    #expect(OpenWindows.pathAsOpened("/Users/example/Projects/alpha")
            == "/Users/example/Projects/alpha")
}
