import SwiftUI

enum Age {
    static func words(since: Date, now: Date = Date()) -> String {
        let secs = max(0, now.timeIntervalSince(since))
        if secs < 60 { return L.string("age.justNow") }
        let mins = Int(secs / 60)
        if mins < 60 { return L.format("age.minutes", mins) }
        let hours = mins / 60
        if hours < 24 { return L.format("age.hours", hours) }
        return L.format("age.days", hours / 24)
    }
}

@MainActor
final class PanelModel: ObservableObject {
    @Published private(set) var waiting: [Session] = []
    @Published private(set) var finished: [Session] = []
    @Published private(set) var working: [Session] = []
    @Published private(set) var idleProjects: [Project] = []
    @Published private(set) var pinnedProjects: [Project] = []
    @Published private(set) var limits: Limits?
    @Published private(set) var counts = Counts()
    /// The version to offer in the menu and About, or `nil` when there's
    /// nothing newer than what's running. Recomputed on every refresh from
    /// whatever `UpdateChecker` last found — see `checkForUpdate()`.
    @Published private(set) var availableUpdate: String?

    /// What's already been opened: session id → when it was opened. Survives a restart.
    @Published private var seen: [String: Date] = {
        let raw = UserDefaults.standard.dictionary(forKey: "seenSessions") as? [String: Double]
        return (raw ?? [:]).mapValues { Date(timeIntervalSince1970: $0) }
    }()

    /// Dot on the right: the session is done, and it hasn't been opened yet.
    func isUnread(_ session: Session) -> Bool {
        guard session.status == .finished else { return false }
        guard let openedAt = seen[session.id] else { return true }
        return session.since > openedAt
    }

    func markSeen(_ session: Session) {
        // the session list is unbounded, but the read-marks aren't
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        seen = seen.filter { $0.value > cutoff }
        seen[session.id] = Date()
        UserDefaults.standard.set(seen.mapValues(\.timeIntervalSince1970),
                                  forKey: "seenSessions")
    }

    /// Garbage in notify/state is swept once an hour, not every two seconds.
    private var sweptAt: Date = .distantPast

    private let git = GitBranch()
    private var branchCache: [String: String] = [:]
    private var timer: Timer?
    let configStore: ConfigStore
    // Guards against `refresh()` — running every 2 seconds — firing a
    // second GitHub request while the first one is still in flight (the
    // 10-second timeout is long enough for that to happen easily).
    private var updateCheckInFlight = false

    init(configStore: ConfigStore = ConfigStore()) {
        self.configStore = configStore
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        let now = Date()
        if now.timeIntervalSince(sweptAt) > 3600 {
            sweptAt = now
            StateReader.sweep(now: now)
        }
        // Cheap enough to do every cycle, and simpler and more reliable than
        // watching the file descriptor — see ConfigStore.load().
        configStore.load()
        let config = configStore.config

        // The sessions folder is user-configurable (Settings ▸ Files). Only
        // touch the shared root — and drop the cached project list — when
        // it actually changed, so a no-op reload every 2 seconds doesn't
        // invalidate caches for no reason.
        let sessionsRoot = URL(fileURLWithPath: (config.sessionsPath as NSString).expandingTildeInPath)
        if TranscriptIndex.root != sessionsRoot {
            TranscriptIndex.root = sessionsRoot
            ProjectPaths.invalidateCache()
        }

        let lookup = ProjectMatching.lookup(config)
        let states = StateReader.readAll()
        let quiets = StateReader.readQuiet()
        let transcripts = TranscriptIndex.index()

        var sessions: [Session] = []
        for (id, entry) in transcripts {   // index() already returned only live ones
            // The actual decision lives in StatusRules: markers ⚠️ and ❓ are never
            // removed and can stick around, the .quiet sentinel is a leftover from
            // the previous turn, and a transcript with no Claude entry at all isn't
            // a session. nil means: don't show it.
            guard let verdict = StatusRules.decide(.init(
                touched: entry.touched,
                marker: states[id],
                quiet: quiets[id],
                working: TranscriptIndex.isWorking(entry))) else { continue }

            sessions.append(Session(id: id,
                                    path: entry.path,
                                    status: verdict.status,
                                    since: verdict.since,
                                    touched: entry.touched,
                                    project: ProjectMatching.knownProject(at: entry.path, config: lookup),
                                    branch: branchCache[entry.path]))
        }

        // Claude Code creates a separate session file not just per window: service
        // launches and background-task wakeups get their own transcript too. Because
        // of this, one project could show up as three separate rows. The click still
        // leads to the same folder either way, so only one row is kept per project.
        //
        // What to show when a folder has several sessions.
        //
        // A pending request always wins, even over the oldest one: markers ⚠️ and ❓
        // only count if nothing was written to the transcript after them — which
        // means that session really is stuck waiting, and can't be stale.
        //
        // Between "done" and "working", the deciding factor is the time of the last
        // write, not importance. "Done" can't outrank "working": a session could
        // write in the same second, and the row would show "done 39 minutes ago" —
        // telling the user everything had stopped when work was still going on.
        sessions = Dictionary(grouping: sessions, by: \.path).values.compactMap { group in
            group.max { a, b in
                (a.status.waitsForHer ? 1 : 0, a.touched) < (b.status.waitsForHer ? 1 : 0, b.touched)
            }
        }
        // waiting — newest to oldest, the one that just called out is on top
        waiting  = sessions.filter { $0.status.waitsForHer }.sorted { $0.since > $1.since }
        finished = sessions.filter { $0.status == .finished }.sorted { $0.since > $1.since }
        working  = sessions.filter { $0.status == .working  }.sorted { $0.since > $1.since }

        // Folders open in VS Code with no session of their own — governed by
        // menuMode, and never includes a folder already shown above.
        idleProjects = ProjectMatching.idleProjects(config: config,
                                                     sessionPaths: Set(sessions.map(\.path)),
                                                     openFolders: OpenWindows.folders())
        // Last group in the menu, and only the quiet ones: a pinned project that
        // has a live session — or is already listed as an open VS Code window —
        // is shown above, and must not appear twice.
        let shownAbove = Set(sessions.map(\.path).map(ProjectMatching.normalize))
            .union(idleProjects.map { ProjectMatching.normalize($0.path) })
        pinnedProjects = ProjectMatching.pinnedProjects(config)
            .filter { !shownAbove.contains(ProjectMatching.normalize($0.path)) }

        // Usage numbers only come from the status line, and it isn't invoked in a
        // VS Code session. Stale percentages are worse than none: the block only
        // shows up when the data is fresh, otherwise it's simply not in the menu.
        limits = LimitsReader.read().flatMap {
            Date().timeIntervalSince($0.writtenAt) < 3600 ? $0 : nil
        }
        counts = Counts(waiting: waiting.count, done: finished.count, busy: working.count)

        availableUpdate = UpdateChecker.availableUpdate(latestKnown: config.latestKnownVersion,
                                                         current: AppVersion.current)
        if UpdateChecker.shouldCheck(enabled: config.checkForUpdates,
                                     lastCheckedAt: config.lastUpdateCheckAt,
                                     now: now) {
            Task { await checkForUpdate() }
        }

        Task { await refreshBranches(for: sessions.map(\.path)) }
    }

    /// The one place a network request leaves this app. Runs off the timer
    /// in `refresh()`, guarded by `UpdateChecker.shouldCheck` so it fires at
    /// most once a day and never while the toggle in Settings is off.
    private func checkForUpdate() async {
        guard !updateCheckInFlight else { return }
        updateCheckInFlight = true
        defer { updateCheckInFlight = false }
        let tag = await UpdateChecker.fetchLatestTag()
        configStore.recordUpdateCheck(at: Date(), latestVersion: tag)
    }

    /// git runs off the main thread: on it, it would hang the menu.
    private func refreshBranches(for paths: [String]) async {
        // An answer is needed for EVERY path, including "no branch". Otherwise a
        // removed worktree folder, or a folder that stopped being a repo, would
        // keep showing the old branch name in the menu forever.
        var found: [String: String?] = [:]
        for path in Set(paths) { found[path] = await git.branch(at: path) }
        applyBranches(found)
    }

    private func applyBranches(_ found: [String: String?]) {
        guard !found.isEmpty else { return }
        for (path, branch) in found { branchCache[path] = branch }

        func fill(_ list: [Session]) -> [Session] {
            list.map { session in
                var copy = session
                copy.branch = branchCache[session.path]
                return copy
            }
        }
        waiting = fill(waiting)
        finished = fill(finished)
        working = fill(working)
    }
}
