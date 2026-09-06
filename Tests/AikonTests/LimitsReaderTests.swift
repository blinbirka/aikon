import Testing
import Foundation
@testable import Aikon

@Test func parsesLimitsLine() {
    let l = LimitsReader.parse("22.4 11.1 1788349397 1788370000 1788800000")
    #expect(l?.fiveHourPercent == 22)
    #expect(l?.sevenDayPercent == 11)
    #expect(l?.fiveHourResetsAt == Date(timeIntervalSince1970: 1788370000))
    #expect(l?.sevenDayResetsAt == Date(timeIntervalSince1970: 1788800000))
}

@Test func dashInsteadOfResetTimeGivesNil() {
    let l = LimitsReader.parse("22.4 11.1 1788349397 - -")
    #expect(l?.fiveHourPercent == 22)
    #expect(l?.fiveHourResetsAt == nil)
    #expect(l?.sevenDayResetsAt == nil)
}

@Test func malformedLineFailsToParse() {
    #expect(LimitsReader.parse("- - -") == nil)
    #expect(LimitsReader.parse("") == nil)
}
