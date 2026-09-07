import SwiftUI

/// The one `UserDefaults` operation `PanelModel.seen` needs. Kept this narrow
/// so an in-memory test double is trivial to write — see
/// `PanelModel.defaults` for why that matters.
protocol UnreadStore: AnyObject {
    func dictionary(forKey key: String) -> [String: Any]?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: UnreadStore {}

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
    /// Nothing at all to show — no sessions, no folders, no usage numbers.
    @Published private(set) var isEmpty = false
    /// Empty *and* the status hook was never installed, so the empty state can
    /// point at the one step that's actually missing.
    @Published private(set) var needsHookSetup = false
    @Published private(set) var counts = Counts()
    /// The version to offer in the menu and About, or `nil` when there's
    /// nothing newer than what's running. Recomputed on every refresh from
    /// whatever `UpdateChecker` last found — see `checkForUpdate()`.
    @Published private(set) var availableUpdate: String?

    /// What's already been opened: session id → when it was opened. Survives a
    /// restart. Loaded from `defaults` in `init`, since the initial value
    /// depends on which store this instance was built with.
    @Published private var seen: [String: Date] = [:]

    /// Where `seen` is persisted — the one thing `markSeen`/`isUnread` need
    /// from `UserDefaults`. `UserDefaults` itself round-trips through
    /// `cfprefsd`, a system daemon that flushes `~/Library/Preferences/*.plist`
    /// on its own schedule: even a suite created just for one test, then
    /// deleted with `removePersistentDomain`, can have that file resurface
    /// on disk seconds later from a write the daemon had already queued.
    /// Depending on this narrow protocol instead of the concrete class lets
    /// tests hand in a plain in-memory double — see
    /// `PanelModelUnreadTests.InMemoryUnreadStore` — so unread-tracking tests
    /// never touch the real daemon or leave a file behind.
    private var defaults: UnreadStore = UserDefaults.standard

    /// Dot on the right: the session is done, and it hasn't been opened yet.
    func isUnread(_ session: Session) -> Bool {
        guard session.status == .finished else { return false }
        guard let openedAt = seen[session.id] else { return true }
        return session.since > openedAt
    }

    func markSeen(_ session: Session, now: Date = Date()) {
        // the session list is unbounded, but the read-marks aren't
        let cutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        seen = seen.filter { $0.value > cutoff }
        seen[session.id] = now
        defaults.set(seen.mapValues(\.timeIntervalSince1970), forKey: "seenSessions")
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

    /// - Parameters:
    ///   - defaults: backs the unread-tracking `seen` dictionary. Tests pass
    ///     an in-memory double so they never touch the real `UserDefaults` —
    ///     see `PanelModelUnreadTests`.
    ///   - startRefreshing: when `false`, skips the initial `refresh()` call
    ///     and never starts the 2-second timer, so a test can call
    ///     `refresh()` itself, exactly when it wants a pass, instead of
    ///     racing a real background timer it has no handle to stop.
    init(configStore: ConfigStore = ConfigStore(), defaults: UnreadStore = UserDefaults.standard,
         startRefreshing: Bool = true) {
        self.configStore = configStore
        self.defaults = defaults
        let raw = defaults.dictionary(forKey: "seenSessions") as? [String: Double]
        seen = (raw ?? [:]).mapValues { Date(timeIntervalSince1970: $0) }
        guard startRefreshing else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Skips `refresh()` and the timer entirely, and points `configStore` at
    /// a throwaway file instead of the real `~/.config/aikon/config.json` —
    /// this path must never read the user's config, transcripts, git repos,
    /// or open VS Code windows. `seen` stays empty instead of touching
    /// `UserDefaults`, for the same reason. Every published property below is
    /// filled in by hand instead. Used only by `renderPreview()`.
    private init(demo: Void) {
        configStore = ConfigStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("aikon-render-config.json"),
            openFolders: { [] },
            sessionFolders: { [] })
    }

    /// A model stocked with fixed, made-up demo data — no disk, git, or
    /// network access anywhere in it. Built for `RenderScreenshot`, which
    /// draws this into the README's menu screenshot so the picture never
    /// shows the author's real projects.
    static func renderPreview() -> PanelModel {
        let now = Date()
        func project(_ name: String) -> Project {
            Project(path: "/demo/\(name)", name: name, emoji: nil, iconPath: nil)
        }
        func session(_ id: String, _ projectName: String, branch: String,
                     status: SessionStatus, minutesAgo: Double) -> Session {
            let since = now.addingTimeInterval(-minutesAgo * 60)
            return Session(id: id, path: "/demo/\(projectName)", status: status,
                           since: since, touched: since,
                           project: project(projectName), branch: branch)
        }

        let model = PanelModel(demo: ())
        model.waiting = [
            session("demo-website", "Website", branch: "main",
                    status: .needsAnswer, minutesAgo: 2),
            session("demo-api", "API", branch: "api/rate-limits",
                    status: .needsPermission, minutesAgo: 6),
        ]
        model.finished = [
            session("demo-docs", "Docs", branch: "main",
                    status: .finished, minutesAgo: 14),
        ]
        model.working = [
            session("demo-analytics", "Analytics", branch: "spike/funnels",
                    status: .working, minutesAgo: 0),
        ]
        model.pinnedProjects = [project("Design System"), project("Infra"), project("Sandbox")]
        model.counts = Counts(waiting: model.waiting.count,
                              done: model.finished.count,
                              busy: model.working.count)
        return model
    }

    /// `now` drives every freshness check this makes (state markers, the
    /// transcript index, the limits block) — a single instant instead of
    /// several back-to-back `Date()` calls, and the knob a test needs to
    /// place a transcript on either side of the 30-minute/30-day/etc.
    /// cutoffs without racing the real clock.
    func refresh(now: Date = Date()) {
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
        let states = StateReader.readAll(now: now)
        let quiets = StateReader.readQuiet(now: now)
        let transcripts = TranscriptIndex.index(now: now)

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
        // leads to the same folder either way, so only one row is kept per project —
        // see `representative(of:)` for which one.
        sessions = Dictionary(grouping: sessions, by: \.path).values.compactMap(Self.representative(of:))
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
            now.timeIntervalSince($0.writtenAt) < 3600 ? $0 : nil
        }
        counts = Counts(waiting: waiting.count, done: finished.count, busy: working.count)

        // Someone who just installed Aikon and has never run Claude Code would
        // otherwise open a menu holding nothing but Settings… and Quit, with no
        // hint about what's missing. `MenuView` shows an explanation instead —
        // and offers the hook step, but only to someone who hasn't taken it.
        // The settings file is read only in this case, not on every cycle.
        isEmpty = waiting.isEmpty && finished.isEmpty && working.isEmpty
            && idleProjects.isEmpty && pinnedProjects.isEmpty && limits == nil
        if isEmpty, case .notInstalled = HookInstaller.state() {
            needsHookSetup = true
        } else {
            needsHookSetup = false
        }

        availableUpdate = UpdateChecker.availableUpdate(latestKnown: config.latestKnownVersion,
                                                         current: AppVersion.current)
        if UpdateChecker.shouldCheck(enabled: config.checkForUpdates,
                                     lastCheckedAt: config.lastUpdateCheckAt,
                                     now: now) {
            Task { await checkForUpdate() }
        }

        Task { await refreshBranches(for: sessions.map(\.path)) }
    }

    /// What to show when a folder has several sessions — a service launch,
    /// a background-task wakeup, and a real window can each leave their own
    /// transcript for the same folder, and only one row is kept.
    ///
    /// A pending request always wins, even over the oldest one: markers ⚠️ and ❓
    /// only count if nothing was written to the transcript after them — which
    /// means that session really is stuck waiting, and can't be stale.
    ///
    /// Between "done" and "working", the deciding factor is the time of the last
    /// write, not importance. "Done" can't outrank "working": a session could
    /// write in the same second, and the row would show "done 39 minutes ago" —
    /// telling the user everything had stopped when work was still going on.
    static func representative(of group: [Session]) -> Session? {
        group.max { a, b in
            (a.status.waitsForHer ? 1 : 0, a.touched) < (b.status.waitsForHer ? 1 : 0, b.touched)
        }
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
