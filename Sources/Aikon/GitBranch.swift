import Foundation

actor GitBranch {
    private var cache: [String: (branch: String?, at: Date)] = [:]
    private let ttl: TimeInterval = 30

    func branch(at path: String) -> String? {
        if let hit = cache[path], Date().timeIntervalSince(hit.at) < ttl { return hit.branch }
        let value = Self.run(path)
        cache[path] = (value, Date())
        return value
    }

    private static func run(_ path: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", path, "branch", "--show-current"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let s = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? nil : s
    }
}
