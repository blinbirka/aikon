import Foundation

@MainActor
enum ProjectPaths {
    private static var known: (at: Date, paths: [String])?

    /// The list is rebuilt periodically: otherwise a new folder is only visible
    /// after a restart. This is cheap — each file's cwd is already cached by
    /// TranscriptIndex.
    private static let ttl: TimeInterval = 300

    /// Temporary session folders are not projects. Without this check, a project
    /// could open in a scratch/temp folder: a temp folder's name can contain the
    /// project's name too.
    static func isRealProject(_ path: String) -> Bool {
        !path.hasPrefix("/private/tmp") && !path.hasPrefix("/tmp")
            && !path.contains("/scratchpad")
    }

    /// Drops the cached folder list — call this when the transcripts root
    /// changes (the person points Aikon at a different Claude Code sessions
    /// folder in Settings), so the new folder's projects don't wait up to
    /// five minutes to show up.
    static func invalidateCache() { known = nil }

    /// Every folder a session has ever worked in. Built once per refresh.
    /// Sorting by length is required: a project can have several cwds (the root
    /// and a subfolder, or a duplicate copy elsewhere), and without sorting the
    /// choice would depend on filesystem traversal order — i.e. be random.
    /// The shortest path is closest to the project root.
    static func knownPaths(now: Date = Date()) -> [String] {
        if let known, now.timeIntervalSince(known.at) < ttl { return known.paths }
        let fm = FileManager.default
        var out: Set<String> = []
        let dirs = (try? fm.contentsOfDirectory(at: TranscriptIndex.root,
                                                includingPropertiesForKeys: nil)) ?? []
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        for dir in dirs {
            let files = (try? fm.contentsOfDirectory(at: dir,
                                                     includingPropertiesForKeys: Array(keys))) ?? []
            // One folder name maps to DIFFERENT cwds: Claude Code replaces both "/"
            // and "-" with a hyphen, and a folder could previously have been
            // reached through a since-removed shortcut/symlink. A project's
            // transcript directory can contain entries with both paths, and the
            // older one points at a folder that no longer exists. So we walk from
            // the freshest files and take the first cwd whose folder still exists.
            let jsonl = files.filter { $0.pathExtension == "jsonl" }.sorted {
                let a = (try? $0.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
                return a > b
            }
            for file in jsonl.prefix(8) {
                guard let cwd = TranscriptIndex.cwd(ofTranscript: file),
                      isRealProject(cwd),
                      fm.fileExists(atPath: cwd) else { continue }
                out.insert(cwd)
                break
            }
        }
        let paths = out.sorted { ($0.count, $0) < ($1.count, $1) }
        known = (now, paths)
        return paths
    }
}
