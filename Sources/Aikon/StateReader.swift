import Foundation

struct StateFile {
    let uuid: String
    let status: SessionStatus
    let at: Date
}

enum StateReader {
    @MainActor static var dir = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".claude/tools/notify/state")

    /// Nothing cleans up state files: notify.sh writes ⚠️ and ❓ and never deletes
    /// them. The folder accumulates dozens of files a day. Reading the contents of
    /// each one twice a second isn't viable: over a year that's tens of thousands
    /// of files. Anything older than a day can't belong to a live session anyway —
    /// the panel doesn't consider transcripts older than a day either.
    static let markerLimit: TimeInterval = 24 * 60 * 60

    /// Extensions the panel considers its own and is allowed to delete.
    /// The `limits` file lives in the same folder and is excluded from cleanup.
    private static let ourSuffixes = [".⚠️", ".❓", ".🏁", ".quiet"]

    /// Sweeps garbage: `notify.sh` writes markers and never deletes them, so the
    /// folder accumulates dozens of files a day. Anything older than a day can't
    /// belong to a live session — the panel doesn't consider transcripts older
    /// than a day either — and downstream consumers of these files only need them
    /// for the first 60 seconds, to de-duplicate repeats.
    @MainActor @discardableResult
    static func sweep(now: Date = Date()) -> Int {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let urls = (try? fm.contentsOfDirectory(at: dir,
                                                includingPropertiesForKeys: Array(keys))) ?? []
        var removed = 0
        for url in urls {
            let name = url.lastPathComponent
            guard ourSuffixes.contains(where: { name.hasSuffix($0) }) else { continue }
            let m = (try? url.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
            guard now.timeIntervalSince(m) >= markerLimit else { continue }
            if (try? fm.removeItem(at: url)) != nil { removed += 1 }
        }
        return removed
    }

    /// File names in the folder, filtered by freshness BEFORE reading contents.
    @MainActor static func recentNames(now: Date = Date()) -> [String] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: Array(keys))) ?? []
        return urls.compactMap { url in
            let m = (try? url.resourceValues(forKeys: keys).contentModificationDate)
                ?? .distantPast
            guard now.timeIntervalSince(m) < markerLimit else { return nil }
            return url.lastPathComponent
        }
    }

    static func status(fromFileName name: String) -> SessionStatus? {
        guard let dot = name.lastIndex(of: ".") else { return nil }
        switch String(name[name.index(after: dot)...]) {
        case "⚠️": return .needsPermission
        case "❓":  return .needsAnswer
        case "🏁": return .finished
        default:   return nil          // .quiet and everything else
        }
    }

    static func uuid(fromFileName name: String) -> String? {
        guard let dot = name.lastIndex(of: ".") else { return nil }
        return String(name[name.startIndex..<dot])
    }

    /// The event time lives INSIDE the file (unix timestamp). If it can't be
    /// read, fall back to mtime.
    static func eventTime(_ url: URL) -> Date {
        if let text = try? String(contentsOf: url, encoding: .utf8),
           let secs = TimeInterval(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return Date(timeIntervalSince1970: secs)
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.modificationDate] as? Date) ?? .distantPast
    }

    static func latest(_ files: [StateFile]) -> StateFile? {
        files.max { $0.at < $1.at }
    }

    /// `{uuid}.quiet` — a sentinel created when Claude finishes a turn.
    /// As long as it exists and is newer than the last transcript write, the
    /// session is waiting on the person.
    @MainActor static func readQuiet(now: Date = Date()) -> [String: Date] {
        let names = recentNames(now: now)
        var out: [String: Date] = [:]
        for name in names where name.hasSuffix(".quiet") {
            let id = String(name.dropLast(".quiet".count))
            out[id] = eventTime(dir.appending(path: name))
        }
        return out
    }

    @MainActor static func readAll(now: Date = Date()) -> [String: StateFile] {
        let names = recentNames(now: now)
        var byUUID: [String: [StateFile]] = [:]
        for name in names {
            guard let st = status(fromFileName: name),
                  let id = uuid(fromFileName: name) else { continue }
            byUUID[id, default: []].append(
                StateFile(uuid: id, status: st, at: eventTime(dir.appending(path: name)))
            )
        }
        return byUUID.compactMapValues(latest)
    }
}
