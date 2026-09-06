import Testing
@testable import Aikon
import Foundation

@Test @MainActor func oldStateFilesAreNotRead() throws {
    // notify.sh never deletes markers: over a year they'd pile up to 16 thousand,
    // and reading every one's contents twice a second is not an option
    let fm = FileManager.default
    let box = fm.temporaryDirectory.appending(path: "state-\(UUID())")
    try fm.createDirectory(at: box, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: box) }

    let now = Date()
    func put(_ name: String, age: TimeInterval) throws {
        let url = box.appending(path: name)
        try Data("\(Int(now.timeIntervalSince1970 - age))".utf8).write(to: url)
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-age)],
                             ofItemAtPath: url.path)
    }
    try put("fresh.⚠️", age: 600)
    try put("ancient.⚠️", age: 3 * 24 * 3600)
    try put("fresh.quiet", age: 600)

    let saved = StateReader.dir
    defer { StateReader.dir = saved }
    StateReader.dir = box

    let names = StateReader.recentNames(now: now)
    #expect(names.count == 2)
    #expect(!names.contains("ancient.⚠️"))
    #expect(StateReader.readAll(now: now).keys.sorted() == ["fresh"])
    #expect(StateReader.readQuiet(now: now).keys.sorted() == ["fresh"])
}

@Test @MainActor func sweepsOldMarkersAndLeavesLimitsAlone() throws {
    let fm = FileManager.default
    let box = fm.temporaryDirectory.appending(path: "sweep-\(UUID())")
    try fm.createDirectory(at: box, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: box) }

    let now = Date()
    func put(_ name: String, age: TimeInterval) throws {
        let url = box.appending(path: name)
        try Data("x".utf8).write(to: url)
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-age)],
                             ofItemAtPath: url.path)
    }
    try put("fresh.⚠️", age: 600)
    try put("ancient.⚠️", age: 3 * 24 * 3600)
    try put("ancient.❓", age: 3 * 24 * 3600)
    try put("ancient.🏁", age: 3 * 24 * 3600)
    try put("ancient.quiet", age: 3 * 24 * 3600)
    try put("limits", age: 3 * 24 * 3600)   // not one of ours, leave it be

    let saved = StateReader.dir
    defer { StateReader.dir = saved }
    StateReader.dir = box

    #expect(StateReader.sweep(now: now) == 4)
    let left = try fm.contentsOfDirectory(atPath: box.path).sorted()
    #expect(left == ["fresh.⚠️", "limits"])
}
