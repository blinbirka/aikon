import Testing
@testable import Aikon

@Test func catalogIsNotEmptyAndHasKnownEmoji() {
    #expect(!EmojiCatalog.all.isEmpty)
    #expect(EmojiCatalog.all.contains("🚀"))
    #expect(EmojiCatalog.all.contains("📁"))
}

/// `applyingTransform(.toUnicodeName, ...)` hands back `"\N{ROCKET}"` for
/// 🚀 — this checks the `\N{` / `}` stripping and lowercasing on its own.
@Test func nameExtractsFromUnicodeNameFormat() {
    #expect(EmojiCatalog.name(for: "🚀") == "rocket")
}

@Test func searchByEnglishNameFindsEmoji() {
    #expect(EmojiCatalog.search("rocket").contains("🚀"))
}

@Test func searchByRussianSynonymFindsSameEmoji() {
    #expect(EmojiCatalog.search("ракета").contains("🚀"))
}

@Test func emptyQueryReturnsWholeCatalog() {
    #expect(EmojiCatalog.search("").count == EmojiCatalog.all.count)
    #expect(EmojiCatalog.search("   ").count == EmojiCatalog.all.count)
}

@Test func recentsCapAtEightMostRecentFirstNoDuplicates() {
    var recents: [String] = []
    for emoji in ["🚀", "📁", "🐱", "⭐", "🔥", "❄️", "🎯", "🎈"] {
        recents = EmojiCatalog.updatingRecents(recents, adding: emoji)
    }
    #expect(recents.count == 8)
    #expect(recents.first == "🎈")

    // A ninth pick pushes out the oldest and still caps at eight.
    recents = EmojiCatalog.updatingRecents(recents, adding: "🌟")
    #expect(recents.count == 8)
    #expect(recents.first == "🌟")
    #expect(!recents.contains("🚀"))

    // Re-picking something already in the list moves it to the front
    // instead of duplicating it.
    recents = EmojiCatalog.updatingRecents(recents, adding: "📁")
    #expect(recents.first == "📁")
    #expect(recents.filter { $0 == "📁" }.count == 1)
    #expect(recents.count == 8)
}
