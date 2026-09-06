import Testing
@testable import Aikon
import Foundation

private let fakeAppURL = URL(fileURLWithPath: "/Applications/Fake Editor.app")

@Test func fullProductJSONParsesEveryField() {
    let json = """
    {"nameShort":"FakeCode","nameLong":"Fake Code - Insiders",
     "applicationName":"fakecode","urlProtocol":"fakecode",
     "darwinBundleIdentifier":"com.example.fakecode"}
    """
    let editor = Editor.parse(productJSON: Data(json.utf8), infoPlist: nil, appURL: fakeAppURL)
    #expect(editor?.name == "Fake Code - Insiders")
    #expect(editor?.bundleID == "com.example.fakecode")
    #expect(editor?.cliName == "fakecode")
    #expect(editor?.urlScheme == "fakecode")
    #expect(editor?.storageFolderName == "FakeCode")
}

@Test func minimalProductJSONFallsBackToTheAppFilename() {
    // Only applicationName is required by the design; everything else has a
    // sensible fallback so a fork that trims its product.json still works.
    let json = #"{"applicationName":"fakecode"}"#
    let editor = Editor.parse(productJSON: Data(json.utf8), infoPlist: nil, appURL: fakeAppURL)
    #expect(editor?.name == "Fake Editor")
    #expect(editor?.cliName == "fakecode")
    #expect(editor?.urlScheme == "fakecode")
    #expect(editor?.storageFolderName == "fakecode")
    // no darwinBundleIdentifier and no Info.plist: falls all the way back
    #expect(editor?.bundleID == "fakecode")
}

@Test func missingApplicationNameIsNotAnEditor() {
    // A product.json without applicationName isn't a VS Code fork — some
    // other Electron app could ship a file with that name by coincidence.
    let json = #"{"nameShort":"Something"}"#
    #expect(Editor.parse(productJSON: Data(json.utf8), infoPlist: nil, appURL: fakeAppURL) == nil)
}

@Test func malformedJSONIsNotAnEditor() {
    #expect(Editor.parse(productJSON: Data("not json".utf8), infoPlist: nil, appURL: fakeAppURL)
            == nil)
    #expect(Editor.parse(productJSON: nil, infoPlist: nil, appURL: fakeAppURL) == nil)
}

@Test func infoPlistSuppliesTheBundleIDWhenProductJSONDoesNot() {
    let json = #"{"applicationName":"fakecode"}"#
    let plist = ["CFBundleIdentifier": "com.example.fromplist"]
    let editor = Editor.parse(productJSON: Data(json.utf8), infoPlist: plist, appURL: fakeAppURL)
    #expect(editor?.bundleID == "com.example.fromplist")
}

// MARK: - Discovery

@Test func discoveryFindsEditorsAndSkipsNonEditorApps() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "editors-\(UUID())")
    let fooApp = root.appending(path: "Foo.app")
    let barApp = root.appending(path: "Bar.app")
    try FileManager.default.createDirectory(
        at: fooApp.appending(path: "Contents/Resources/app"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
        at: barApp.appending(path: "Contents"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let productJSON = """
    {"nameShort":"Foo","applicationName":"foo","urlProtocol":"foo",
     "darwinBundleIdentifier":"com.example.foo"}
    """
    try Data(productJSON.utf8).write(
        to: fooApp.appending(path: "Contents/Resources/app/product.json"))
    // Bar.app has no product.json at all — a plain, non-VS Code-family app.

    let found = await MainActor.run { Editor.scan(directories: [root]) }
    #expect(found.count == 1)
    #expect(found.first?.name == "Foo")
    #expect(found.first?.bundleID == "com.example.foo")
}

@Test func discoverySkipsAMissingDirectoryInstead() async {
    let missing = FileManager.default.temporaryDirectory.appending(path: "no-such-\(UUID())")
    let found = await MainActor.run { Editor.scan(directories: [missing]) }
    #expect(found.isEmpty)
}

// MARK: - Preference

@MainActor
private func makeEditor(_ name: String, bundleID: String) -> Editor {
    Editor(appURL: URL(fileURLWithPath: "/Applications/\(name).app"), name: name,
           bundleID: bundleID, cliName: name.lowercased(), urlScheme: name.lowercased(),
           storageFolderName: name)
}

@Test @MainActor func runningEditorIsPreferredOverEverythingElse() {
    let a = makeEditor("Alpha", bundleID: "com.example.alpha")
    let b = makeEditor("Beta", bundleID: "com.example.beta")

    let savedRunning = Editor.isRunning
    let savedDates = Editor.storageModificationDate
    defer { Editor.isRunning = savedRunning; Editor.storageModificationDate = savedDates }

    Editor.isRunning = { $0 == "com.example.beta" }
    // Alpha looks more recently used, but a running editor still wins.
    Editor.storageModificationDate = { $0.name == "Alpha" ? Date() : nil }

    #expect(Editor.preferred(among: [a, b])?.name == "Beta")
}

@Test @MainActor func mostRecentlyUsedWinsWhenNoneAreRunning() {
    let a = makeEditor("Alpha", bundleID: "com.example.alpha")
    let b = makeEditor("Beta", bundleID: "com.example.beta")

    let savedRunning = Editor.isRunning
    let savedDates = Editor.storageModificationDate
    defer { Editor.isRunning = savedRunning; Editor.storageModificationDate = savedDates }

    Editor.isRunning = { _ in false }
    let now = Date()
    Editor.storageModificationDate = { $0.name == "Beta" ? now : now.addingTimeInterval(-3600) }

    #expect(Editor.preferred(among: [a, b])?.name == "Beta")
}

@Test @MainActor func alphabeticalOrderIsTheLastResort() {
    let a = makeEditor("Alpha", bundleID: "com.example.alpha")
    let b = makeEditor("Beta", bundleID: "com.example.beta")

    let savedRunning = Editor.isRunning
    let savedDates = Editor.storageModificationDate
    defer { Editor.isRunning = savedRunning; Editor.storageModificationDate = savedDates }

    Editor.isRunning = { _ in false }
    Editor.storageModificationDate = { _ in nil }

    // Deterministic regardless of the order editors were discovered in.
    #expect(Editor.preferred(among: [b, a])?.name == "Alpha")
}

@Test @MainActor func noEditorsMeansNoPreference() {
    #expect(Editor.preferred(among: []) == nil)
}
