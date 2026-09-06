import Foundation

struct Limits: Equatable {
    var fiveHourPercent: Int
    var sevenDayPercent: Int
    var writtenAt: Date
    var fiveHourResetsAt: Date?   // nil if the background job didn't find the field
    var sevenDayResetsAt: Date?
}

enum LimitsReader {
    // A mutable var, not a let: tests point this at a throwaway file instead
    // of the real `~/.claude/tools/notify/state/limits` — same pattern as
    // `StateReader.dir`.
    @MainActor static var file = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".claude/tools/notify/state/limits")

    /// Line format: "H5 D7 writtenAt reset5 reset7".
    /// Percentages arrive as fractions, reset times as unix seconds, a dash means no data.
    static func parse(_ text: String) -> Limits? {
        let parts = text.split(separator: " ").map(String.init)
        guard parts.count >= 3,
              let h5 = Double(parts[0]), let d7 = Double(parts[1]),
              let at = TimeInterval(parts[2]) else { return nil }

        func reset(_ index: Int) -> Date? {
            guard parts.count > index,
                  let secs = TimeInterval(parts[index]), secs > 0 else { return nil }
            return Date(timeIntervalSince1970: secs)
        }

        return Limits(fiveHourPercent: Int(h5.rounded()),
                      sevenDayPercent: Int(d7.rounded()),
                      writtenAt: Date(timeIntervalSince1970: at),
                      fiveHourResetsAt: reset(3),
                      sevenDayResetsAt: reset(4))
    }

    @MainActor static func read() -> Limits? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return parse(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
