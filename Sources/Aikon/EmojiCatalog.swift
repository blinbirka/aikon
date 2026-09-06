import Foundation

/// The emoji set shown in the icon picker's own grid, plus the little bit of
/// search logic that goes with it. Everything here comes straight off
/// `Unicode.Scalar` — no bundled list, no third-party dependency.
enum EmojiCatalog {

    /// Every codepoint in the three main emoji blocks that renders with an
    /// emoji (not text) presentation, in codepoint order. Computed once per
    /// process — the popover reads this, it never recomputes it.
    static let all: [String] = {
        var result: [String] = []
        for block in [0x1F300...0x1FAFF, 0x2600...0x27BF, 0x1F000...0x1F0FF] {
            for codepoint in block {
                guard let scalar = Unicode.Scalar(codepoint), scalar.properties.isEmojiPresentation else { continue }
                result.append(String(scalar))
            }
        }
        return result
    }()

    /// Lowercased Unicode name for each emoji in `all` ("rocket" for 🚀,
    /// etc.), cached alongside it — `applyingTransform` isn't free, and this
    /// is what every search checks against.
    private static let names: [String: String] = {
        var map: [String: String] = [:]
        for emoji in all {
            map[emoji] = name(for: emoji)
        }
        return map
    }()

    /// Pulls the plain-English name out of
    /// `applyingTransform(.toUnicodeName, reverse: false)`'s
    /// `"\N{CLOSED UMBRELLA}"`-shaped output. Exposed on its own so the
    /// extraction can be tested apart from the rest of the catalog.
    static func name(for emoji: String) -> String {
        guard let raw = emoji.applyingTransform(.toUnicodeName, reverse: false) else { return "" }
        var trimmed = raw
        if trimmed.hasPrefix("\\N{") { trimmed.removeFirst(3) }
        if trimmed.hasSuffix("}") { trimmed.removeLast() }
        return trimmed.lowercased()
    }

    /// Common Russian words for the emoji people look for most, mapped to
    /// the English word that actually shows up in the Unicode name. Unicode
    /// names are English-only, so this is what makes searching in Russian
    /// work at all — not exhaustive, just the frequent cases.
    static let russianSynonyms: [String: String] = [
        "папка": "folder", "ракета": "rocket", "книга": "book", "деньги": "money",
        "кот": "cat", "звезда": "star", "огонь": "fire", "сердце": "heart",
        "замок": "lock", "ключ": "key", "дом": "house", "город": "city",
        "график": "chart", "письмо": "envelope", "телефон": "phone",
        "компьютер": "computer", "инструмент": "tool", "коробка": "box",
        "часы": "clock", "календарь": "calendar", "мозг": "brain",
        "робот": "robot", "музыка": "music", "камера": "camera",
        "самолёт": "airplane", "машина": "car",
    ]

    /// Every emoji whose Unicode name contains `query`, case-insensitively —
    /// and, when `query` is itself a known Russian word, its English
    /// `russianSynonyms` mapping instead. An empty (or all-whitespace) query
    /// returns the whole catalog.
    static func search(_ query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return all }
        let needle = russianSynonyms[trimmed] ?? trimmed
        return all.filter { (names[$0] ?? "").contains(needle) }
    }

    /// `current` with `emoji` moved to the front — added if it wasn't
    /// there, de-duplicated if it was — and capped at eight entries.
    static func updatingRecents(_ current: [String], adding emoji: String) -> [String] {
        var updated = current.filter { $0 != emoji }
        updated.insert(emoji, at: 0)
        if updated.count > 8 { updated.removeLast(updated.count - 8) }
        return updated
    }
}
