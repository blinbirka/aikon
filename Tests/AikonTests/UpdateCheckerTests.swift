import Testing
import Foundation
@testable import Aikon

/// Pure logic only — no network in any of these. `fetchLatestTag()` itself
/// isn't exercised here; everything it depends on (parsing, comparing,
/// scheduling) is a plain function tested in isolation instead.
@Suite struct UpdateCheckerVersionComparisonTests {
    @Test func longerMinorVersionOutranksShorterOne() {
        // A string compare would get this backwards ("0.10.0" < "0.9.0").
        #expect(UpdateChecker.isNewer("0.10.0", than: "0.9.0"))
    }

    @Test func higherMajorVersionOutranksHigherPatch() {
        #expect(UpdateChecker.isNewer("1.0.0", than: "0.9.9"))
    }

    @Test func equalVersionsAreNotNewer() {
        #expect(!UpdateChecker.isNewer("0.2.0", than: "0.2.0"))
    }

    @Test func olderVersionIsNotNewer() {
        #expect(!UpdateChecker.isNewer("0.1.0", than: "0.2.0"))
    }

    @Test func leadingVPrefixDoesNotAffectComparison() {
        #expect(UpdateChecker.isNewer("v0.3.0", than: "0.2.0"))
        #expect(UpdateChecker.isNewer("0.3.0", than: "v0.2.0"))
        #expect(!UpdateChecker.isNewer("v0.2.0", than: "0.2.0"))
    }
}

@Suite struct UpdateCheckerAvailabilityTests {
    @Test func nothingKnownMeansNoUpdateAvailable() {
        #expect(UpdateChecker.availableUpdate(latestKnown: nil, current: "0.1.0") == nil)
    }

    @Test func newerKnownVersionIsReportedAvailable() {
        #expect(UpdateChecker.availableUpdate(latestKnown: "0.2.0", current: "0.1.0") == "0.2.0")
    }

    @Test func sameOrOlderKnownVersionIsNotAnUpdate() {
        #expect(UpdateChecker.availableUpdate(latestKnown: "0.1.0", current: "0.1.0") == nil)
        #expect(UpdateChecker.availableUpdate(latestKnown: "0.0.9", current: "0.1.0") == nil)
    }
}

@Suite struct UpdateCheckerParsingTests {
    @Test func extractsTagNameFromAFixedReleaseResponse() {
        let json = """
        {"tag_name": "v0.2.0", "name": "0.2.0", "draft": false, "prerelease": false}
        """
        #expect(UpdateChecker.latestVersion(fromReleaseJSON: Data(json.utf8)) == "0.2.0")
    }

    @Test func garbageInsteadOfJSONDoesNotCrashAndReadsAsNoUpdate() {
        let garbage = Data("this is not json at all { [ }} 🙃".utf8)
        #expect(UpdateChecker.latestVersion(fromReleaseJSON: garbage) == nil)
    }

    @Test func validJSONMissingTagNameReadsAsNoUpdate() {
        let json = """
        {"name": "0.2.0"}
        """
        #expect(UpdateChecker.latestVersion(fromReleaseJSON: Data(json.utf8)) == nil)
    }

    @Test func emptyDataReadsAsNoUpdate() {
        #expect(UpdateChecker.latestVersion(fromReleaseJSON: Data()) == nil)
    }
}

@Suite struct UpdateCheckerSchedulingTests {
    @Test func firstCheckEverIsAllowed() {
        #expect(UpdateChecker.shouldCheck(enabled: true, lastCheckedAt: nil, now: Date()))
    }

    @Test func doesNotRunAgainWithinTheInterval() {
        let now = Date()
        #expect(!UpdateChecker.shouldCheck(enabled: true,
                                           lastCheckedAt: now.addingTimeInterval(-3600), now: now))
        // A day and a half in: still too soon, the interval is three days.
        #expect(!UpdateChecker.shouldCheck(enabled: true,
                                           lastCheckedAt: now.addingTimeInterval(-36 * 3600), now: now))
    }

    @Test func runsAgainOnceThreeDaysHavePassed() {
        let now = Date()
        let overThreeDaysAgo = now.addingTimeInterval(-73 * 3600)
        #expect(UpdateChecker.shouldCheck(enabled: true, lastCheckedAt: overThreeDaysAgo, now: now))
    }

    @Test func disabledNeverChecksNoMatterTheDate() {
        #expect(!UpdateChecker.shouldCheck(enabled: false, lastCheckedAt: nil, now: Date()))
        let longAgo = Date().addingTimeInterval(-1000 * 24 * 3600)
        #expect(!UpdateChecker.shouldCheck(enabled: false, lastCheckedAt: longAgo, now: Date()))
    }
}
