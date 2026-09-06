import Foundation

@MainActor
enum TranscriptIndex {
    static var root = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".claude/projects")

    /// A session is considered dead if its transcript hasn't changed for longer
    /// than this.
    static let staleAfter: TimeInterval = 30 * 60

    /// Cutoff for a session in an open window: after a full day, the folder is
    /// assumed to hold different work already.
    static let openWindowLimit: TimeInterval = 24 * 60 * 60

    struct Entry { let path: String; let touched: Date; let file: URL }

    private static let chunkSize = 256 * 1024
    private static let keys: Set<URLResourceKey> = [.contentModificationDateKey]
    private static var cwdCache: [String: String?] = [:]  // file path → cwd (nil = looked up, not found)

    /// A file chunk almost always cuts a multi-byte character in half, and strict
    /// decoding (`String(data:encoding:.utf8)`) returns nil for the WHOLE chunk,
    /// not just one character. This used to break a noticeable fraction of daily
    /// transcripts: the panel couldn't read the status and showed "working"
    /// instead of "done". Decoding here is lenient instead — a broken fragment
    /// only corrupts its own line, and that line gets filtered out during JSON
    /// parsing anyway.
    static func text(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    /// Looks for "cwd" in a chunk of text, parsing line by line.
    static func findCWD(in data: Data) -> String? {
        for line in text(data).components(separatedBy: .newlines) {
            guard let d = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let cwd = obj["cwd"] as? String, !cwd.isEmpty else { continue }
            return cwd
        }
        return nil
    }

    /// Reads cwd from the transcript — does NOT reconstruct a path from the folder
    /// name. Checks the start of the file first, then the tail. The result is
    /// cached: a file's cwd never changes.
    static func cwd(ofTranscript url: URL) -> String? {
        if let hit = cwdCache[url.path] { return hit }   // including a remembered "not found"
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var found: String?
        if let head = try? handle.read(upToCount: chunkSize) {
            found = findCWD(in: head)
        }
        if found == nil,
           let size = try? handle.seekToEnd(), size > UInt64(chunkSize) {
            try? handle.seek(toOffset: size - UInt64(chunkSize))
            if let tail = try? handle.readToEnd() {
                found = findCWD(in: tail)
            }
        }
        // A project folder can be reachable through a symlink, and Claude Code
        // records in cwd whatever path it was launched from. VS Code treats a
        // symlink and its target as DIFFERENT folders and opens a second window
        // instead of switching to the one already open. So the path is
        // canonicalized right away.
        if let raw = found {
            found = URL(fileURLWithPath: raw).resolvingSymlinksInPath().path
        }

        // A failure is remembered too: otherwise the same half-megabyte gets
        // re-read on every list rebuild, and the log fills up with warnings
        // forever.
        cwdCache[url.path] = found
        if found == nil {
            FileHandle.standardError.write(
                Data("panel: couldn't find cwd in \(url.lastPathComponent), session skipped\n".utf8))
        }
        return found
    }

    private static var workingCache: [String: (touched: Date, working: Bool?)] = [:]

    /// Whether a session is working right now or waiting on the person.
    ///
    /// Transcript silence alone doesn't work for this: a session can go several
    /// minutes without writing a line while it's waiting on a tool result, and
    /// the panel would call it done. The precise signal lives in Claude's very
    /// last entry: `stop_reason == "tool_use"` means "called a tool, work is
    /// ongoing", `end_turn` means "turn is over". Any user entry — a prompt or a
    /// tool response — also counts as work: Claude was called, no reply yet.
    /// nil means "there's no Claude entry at all in this chunk" — nothing to
    /// judge from.
    static func working(inTail data: Data) -> Bool? {
        for line in text(data).components(separatedBy: .newlines).reversed() {
            guard let raw = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: raw)
                    as? [String: Any],
                  let message = object["message"] as? [String: Any]
            else { continue }

            if object["type"] as? String == "assistant",
               let stop = message["stop_reason"] as? String {
                return stop == "tool_use"
            }
            // A user entry means: Claude was called and hasn't replied yet.
            // Previously only a tool response counted, and a plain typed prompt
            // didn't: parsing kept walking further back, hit the `end_turn` of
            // the previous turn, and the whole time Claude was thinking, the
            // panel showed "done". In a sample of 60 transcripts: block-array
            // content was 2239 tool responses, 189 text prompts, 12 with an image
            // or document; string content was 36 background-task wakeups
            // (<task-notification>) and 18 of Claude Code's own internal traces
            // (<local-command-…>, <command-…>) left behind by /clear.
            if object["type"] as? String == "user" {
                if message["content"] is [[String: Any]] { return true }
                if let text = message["content"] as? String,
                   !text.hasPrefix("<local-command-"), !text.hasPrefix("<command-") {
                    return true          // <task-notification> — a wakeup, also counts as a turn
                }
                continue                 // <local-command-…> — a /clear trace, not a turn
            }
        }
        return nil
    }

    static func isWorking(_ entry: Entry) -> Bool? {
        if let hit = workingCache[entry.file.path], hit.touched == entry.touched {
            return hit.working
        }

        var answer: Bool?
        if let handle = try? FileHandle(forReadingFrom: entry.file) {
            defer { try? handle.close() }
            let window: UInt64 = 128 * 1024
            let size = (try? handle.seekToEnd()) ?? 0
            try? handle.seek(toOffset: size > window ? size - window : 0)
            if let data = try? handle.readToEnd() { answer = working(inTail: data) }
        }

        workingCache[entry.file.path] = (entry.touched, answer)
        return answer
    }

    /// All LIVE transcripts, indexed by uuid.
    /// Freshness is checked on the FILE (not the folder) and BEFORE reading
    /// contents: a project tree can hold hundreds of transcripts, and reading
    /// them all every 2 seconds isn't viable.
    static func index(now: Date = Date()) -> [String: Entry] {
        let fm = FileManager.default
        var out: [String: Entry] = [:]
        let dirs = (try? fm.contentsOfDirectory(at: root,
                                                includingPropertiesForKeys: nil)) ?? []
        // computed once per cycle, not once per file
        let openFolders = OpenWindows.folders()

        for dir in dirs {
            let files = (try? fm.contentsOfDirectory(at: dir,
                                                     includingPropertiesForKeys: Array(keys))) ?? []
            for file in files where file.pathExtension == "jsonl" {
                let touched = (try? file.resourceValues(forKeys: keys).contentModificationDate)
                    ?? .distantPast
                let age = now.timeIntervalSince(touched)
                // reading the contents is only worth it for files that aren't ancient
                guard age < openWindowLimit else { continue }

                let id = file.deletingPathExtension().lastPathComponent
                if let old = out[id], old.touched > touched { continue }
                guard let path = cwd(ofTranscript: file) else { continue }
                // The same uuid can exist in two ~/.claude/projects folders at once:
                // a small stub in a stale directory and the real, full-sized file in
                // the current one. The stub can be newer by timestamp and would win
                // otherwise. Filtering by folder existence also removes rows whose
                // click wouldn't lead anywhere anyway.
                // A temporary session folder is not a project: clicking such a row
                // would open a scratch/temp path in VS Code. This filter already
                // existed for idle projects; live sessions were missing it.
                guard fm.fileExists(atPath: path), ProjectPaths.isRealProject(path)
                else { continue }

                // A session stays in the menu as long as its folder is open in
                // VS Code. Otherwise — only while the transcript is fresh: a
                // closed window has no place in the list.
                let windowOpen = openFolders.contains(path)
                guard windowOpen || age < staleAfter else { continue }

                out[id] = Entry(path: path, touched: touched, file: file)
            }
        }
        return out
    }
}
