import Testing
@testable import Aikon
import Foundation

@Test func ageInWords() {
    let now = Date()
    #expect(Age.words(since: now.addingTimeInterval(-30),    now: now) == "just now")
    #expect(Age.words(since: now.addingTimeInterval(-120),   now: now) == "2 min")
    #expect(Age.words(since: now.addingTimeInterval(-7200),  now: now) == "2 h")
    #expect(Age.words(since: now.addingTimeInterval(-172800), now: now) == "2 d")
}
