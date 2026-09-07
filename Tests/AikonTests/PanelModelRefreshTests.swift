import Testing
@testable import Aikon
import Foundation

// `refresh()` is the glue: it combines StateReader, TranscriptIndex,
// StatusRules, ProjectMatching, ConfigStore and GitBranch into what the menu
// shows, and nothing called it directly before this file. Every static root
// these read from (TranscriptIndex.root, StateReader.dir, LimitsReader.file)
// is pointed at a throwaway sandbox and restored afterwards, the same
// mutable-static injection style already used by StateFreshnessTests.

private struct Sandbox {
    let root: URL             // fake ~/.claude/projects
    let stateDir: URL         // fake ~/.claude/tools/notify/state
    let configStore: ConfigStore
}

@MainActor
private func withSandbox(_ body: (Sandbox) throws -> Void) rethrows {
    let box = FileManager.default.temporaryDirectory.appendingPathComponent("aikon-refresh-test-\(UUID())")
    let root = box.appendingPathComponent("projects")
    let stateDir = box.appendingPathComponent("state")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)

    let savedRoot = TranscriptIndex.root
    let savedStateDir = StateReader.dir
    let savedLimitsFile = LimitsReader.file
    let savedIsRunning = OpenWindows.isVSCodeRunning
    let savedSettingsURL = HookInstaller.settingsURL
    TranscriptIndex.root = root
    StateReader.dir = stateDir
    LimitsReader.file = box.appendingPathComponent("limits-not-written")
    // `refresh()` asks whether the status hook is installed, to decide what the
    // empty menu should offer. Pointed at the sandbox so it never reads — or
    // reports on — the real `~/.claude/settings.json`. Missing file here means
    // "not installed", which is what a fresh machine looks like.
    HookInstaller.settingsURL = box.appendingPathComponent("settings.json")
    OpenWindows.isVSCodeRunning = { false }
    OpenWindows.forgetCache()
    ProjectPaths.invalidateCache()

    // A config seeded from nothing, pointed at the fake root — never the
    // real `~/.config/aikon/config.json`, `~/.claude`, or VS Code windows —
    // and with update checks off so `refresh()` never makes a real network
    // request in a test.
    let configStore = ConfigStore(fileURL: box.appendingPathComponent("config.json"),
                                  openFolders: { [] }, sessionFolders: { [] })
    configStore.setSessionsPath(root.path)
    configStore.setCheckForUpdates(false)

    defer {
        TranscriptIndex.root = savedRoot
        StateReader.dir = savedStateDir
        LimitsReader.file = savedLimitsFile
        OpenWindows.isVSCodeRunning = savedIsRunning
        HookInstaller.settingsURL = savedSettingsURL
        OpenWindows.forgetCache()
        ProjectPaths.invalidateCache()
        try? FileManager.default.removeItem(at: box)
    }
    try body(Sandbox(root: root, stateDir: stateDir, configStore: configStore))
}

@MainActor
private func throwawayModel(_ sandbox: Sandbox) -> PanelModel {
    PanelModel(configStore: sandbox.configStore,
              defaults: InMemoryUnreadStore(),
              startRefreshing: false)
}

private func sessionFolder(in root: URL, name: String = UUID().uuidString) throws -> URL {
    let dir = root.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@discardableResult
private func writeTranscript(in dir: URL, uuid: String = UUID().uuidString, cwd: String,
                             mtime: Date, lastLine: String) throws -> URL {
    let file = dir.appendingPathComponent("\(uuid).jsonl")
    let lines = [#"{"type":"user","cwd":"\#(cwd)"}"#, lastLine]
    try Data(lines.joined(separator: "\n").utf8).write(to: file)
    try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: file.path)
    return file
}

private let workingLine = #"{"type":"assistant","message":{"stop_reason":"tool_use"}}"#
private let finishedLine = #"{"type":"assistant","message":{"stop_reason":"end_turn"}}"#

private func realFolder(in root: URL, name: String) throws -> String {
    let dir = root.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return ProjectMatching.normalize(dir.path)
}

@Test @MainActor func refreshWithNothingOnDiskProducesAnEmptyMenu() {
    withSandbox { sandbox in
        let model = throwawayModel(sandbox)
        model.refresh()
        #expect(model.waiting.isEmpty)
        #expect(model.finished.isEmpty)
        #expect(model.working.isEmpty)
        #expect(model.idleProjects.isEmpty)
        #expect(model.pinnedProjects.isEmpty)
        #expect(model.limits == nil)
        #expect(model.counts == Counts())
    }
}

/// The required case from the audit: two transcripts for the same folder —
/// a service launch and the real window — must collapse into a single row,
/// and the live one must win over the merely-finished one even though it's
/// the older of the two (see `PanelModel.representative(of:)`).
@Test @MainActor func refreshGroupsSessionsInOneFolderAndPicksTheRepresentative() throws {
    try withSandbox { sandbox in
        let now = Date()
        let path = try realFolder(in: sandbox.root, name: "shared-project")

        try writeTranscript(in: try sessionFolder(in: sandbox.root), cwd: path,
                            mtime: now, lastLine: workingLine)
        try writeTranscript(in: try sessionFolder(in: sandbox.root), cwd: path,
                            mtime: now.addingTimeInterval(-39 * 60), lastLine: finishedLine)

        let model = throwawayModel(sandbox)
        model.refresh(now: now)

        #expect(model.working.map(\.path) == [path])
        #expect(model.finished.isEmpty)
        #expect(model.counts == Counts(waiting: 0, done: 0, busy: 1))
    }
}

/// A pending request outranks a fresher write to the transcript: the marker
/// only goes stale if something was written to the transcript AFTER it.
@Test @MainActor func refreshLetsAPendingMarkerWinOverAFresherFinishedCopy() throws {
    try withSandbox { sandbox in
        let now = Date()
        let path = try realFolder(in: sandbox.root, name: "waiting-project")
        let waitingID = UUID().uuidString

        // Both transcripts stay under the 30-minute staleness cutoff — this
        // test is only about the marker outranking a fresher write, not
        // about `TranscriptIndex.index()`'s own freshness filter.
        try writeTranscript(in: try sessionFolder(in: sandbox.root), uuid: waitingID, cwd: path,
                            mtime: now.addingTimeInterval(-25 * 60), lastLine: finishedLine)
        try writeTranscript(in: try sessionFolder(in: sandbox.root), cwd: path,
                            mtime: now.addingTimeInterval(-18 * 60), lastLine: finishedLine)

        // notify.sh's marker for the waiting transcript: content is the
        // unix timestamp it fired at, matching StateReaderTests' fixtures.
        let markerAt = now.addingTimeInterval(-25 * 60)
        let marker = sandbox.stateDir.appendingPathComponent("\(waitingID).⚠️")
        try Data("\(Int(markerAt.timeIntervalSince1970))".utf8).write(to: marker)
        try FileManager.default.setAttributes([.modificationDate: markerAt], ofItemAtPath: marker.path)

        let model = throwawayModel(sandbox)
        model.refresh(now: now)

        #expect(model.waiting.map(\.path) == [path])
        #expect(model.finished.isEmpty)
    }
}

/// Stale percentages are worse than none: `limits` only surfaces when the
/// status-line data is less than an hour old.
@Test @MainActor func refreshOnlyShowsLimitsWhenFresh() throws {
    try withSandbox { sandbox in
        let now = Date()
        try Data("40 60 \(Int(now.timeIntervalSince1970)) 0 0".utf8).write(to: LimitsReader.file)

        let model = throwawayModel(sandbox)
        model.refresh(now: now)
        #expect(model.limits?.fiveHourPercent == 40)

        model.refresh(now: now.addingTimeInterval(2 * 3600))
        #expect(model.limits == nil)
    }
}

// A machine that has just installed Aikon and never run Claude Code produced a
// menu holding nothing but Settings… and Quit — nothing said why, and nothing
// pointed at the one setup step that was still missing. `isEmpty` and
// `needsHookSetup` are what MenuView shows an explanation from.

@Test @MainActor
func aFreshMachineWithNothingRunningIsReportedAsEmpty() throws {
    try withSandbox { sandbox in
        let model = throwawayModel(sandbox)
        model.refresh()

        #expect(model.isEmpty)
        #expect(model.waiting.isEmpty && model.finished.isEmpty && model.working.isEmpty)
    }
}

@Test @MainActor
func anEmptyMenuOffersTheHookStepWhileTheHookIsMissing() throws {
    try withSandbox { sandbox in
        let model = throwawayModel(sandbox)
        model.refresh()

        #expect(model.needsHookSetup)
    }
}

@Test @MainActor
func theHookStepIsNotOfferedOnceTheHookIsInstalled() throws {
    try withSandbox { sandbox in
        let box = HookInstaller.settingsURL.deletingLastPathComponent()
        try HookInstaller.install(settingsURL: HookInstaller.settingsURL,
                                  hookDestURL: box.appendingPathComponent("aikon-hook.sh"))

        let model = throwawayModel(sandbox)
        model.refresh()

        #expect(model.isEmpty)
        #expect(!model.needsHookSetup)
    }
}

@Test @MainActor
func oneLiveSessionMeansTheMenuIsNotEmpty() throws {
    try withSandbox { sandbox in
        let now = Date()
        let path = try realFolder(in: sandbox.root, name: "a-project")
        try writeTranscript(in: try sessionFolder(in: sandbox.root), cwd: path,
                            mtime: now, lastLine: workingLine)

        let model = throwawayModel(sandbox)
        model.refresh(now: now)

        #expect(!model.isEmpty)
        #expect(!model.needsHookSetup)
    }
}
