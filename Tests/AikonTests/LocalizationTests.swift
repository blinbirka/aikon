import Testing
@testable import Aikon
import Foundation

/// The language picker in settings used to write the choice to disk and stop
/// there: every string still came from `Bundle.module`, which follows the
/// system language. Picking "Русский" on an English Mac changed nothing.
@Suite(.serialized)
struct LocalizationTests {
    private let key = "menu.quit"

    @Test func russianOverrideReturnsRussianText() {
        L.language = .ru
        defer { L.language = .system }
        let text = L.string(key)
        #expect(text != key, "key came back untranslated — the ru bundle wasn't found")
        #expect(text.contains(where: { $0.isCyrillic }), "expected Russian text, got \(text)")
    }

    @Test func englishOverrideReturnsEnglishText() {
        L.language = .en
        defer { L.language = .system }
        let text = L.string(key)
        #expect(text != key)
        #expect(!text.contains(where: { $0.isCyrillic }), "expected English text, got \(text)")
    }

    @Test func switchingBackAndForthKeepsWorking() {
        defer { L.language = .system }
        L.language = .ru
        let ru = L.string(key)
        L.language = .en
        let en = L.string(key)
        #expect(ru != en, "both languages returned the same string: \(ru)")
    }

    @Test func everyKeyExistsInBothLanguages() {
        defer { L.language = .system }
        for key in ["menu.quit", "menu.settings", "status.working", "status.finished"] {
            L.language = .ru
            #expect(L.string(key) != key, "\(key) missing from ru")
            L.language = .en
            #expect(L.string(key) != key, "\(key) missing from en")
        }
    }
}

private extension Character {
    var isCyrillic: Bool { unicodeScalars.allSatisfy { (0x0400...0x04FF).contains($0.value) } }
}

/// Guards against the bug these tests were written for coming back: a view
/// reaching past `L` for its strings (`Text("…", bundle: .module)`,
/// `NSLocalizedString`, `String(localized:)`) always follows the system
/// language instead of the one picked in settings.
@Suite(.serialized)
struct LocalizationGuardTests {
    /// `Sources/Aikon`, found relative to this test file so the path
    /// survives the repo moving or being checked out elsewhere.
    private var sourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // this file -> Tests/AikonTests
            .deletingLastPathComponent() // -> Tests
            .deletingLastPathComponent() // -> repo root
            .appendingPathComponent("Sources/Aikon")
    }

    private func swiftFiles() throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: sourcesDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
    }

    @Test func noLocalizationBypassOutsideL() throws {
        let forbidden = ["bundle: .module", "NSLocalizedString", "String(localized:"]
        for file in try swiftFiles() where file.lastPathComponent != "L.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for pattern in forbidden {
                #expect(!text.contains(pattern), "\(file.lastPathComponent) reaches past L via \"\(pattern)\"")
            }
        }
    }

    /// Every key used through `L.string("…")` / `L.format("…", …)`, found by
    /// scanning the literal calls — not by tracing keys passed in as
    /// variables.
    private func usedKeys() throws -> Set<String> {
        let regex = try NSRegularExpression(pattern: #"L\.(?:string|format)\(\s*"([^"]+)""#)
        var keys = Set<String>()
        for file in try swiftFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                guard let keyRange = Range(match.range(at: 1), in: text) else { continue }
                keys.insert(String(text[keyRange]))
            }
        }
        return keys
    }

    private func translations(for language: String) throws -> [String: String] {
        let path = sourcesDirectory.appending(path: "Resources/\(language).lproj/Localizable.strings")
        guard let dict = NSDictionary(contentsOf: path) as? [String: String] else {
            Issue.record("could not load \(language).lproj/Localizable.strings")
            return [:]
        }
        return dict
    }

    @Test func everyUsedKeyHasAnEnglishTranslation() throws {
        let en = try translations(for: "en")
        for key in try usedKeys() {
            #expect(en[key] != nil, "\"\(key)\" is used in code but missing from en.lproj")
        }
    }

    @Test func everyUsedKeyHasARussianTranslation() throws {
        let ru = try translations(for: "ru")
        for key in try usedKeys() {
            #expect(ru[key] != nil, "\"\(key)\" is used in code but missing from ru.lproj")
        }
    }
}
