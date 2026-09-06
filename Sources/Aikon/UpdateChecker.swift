import Foundation

/// Asks GitHub, at most once a day, whether a newer tagged release exists.
///
/// Every failure — no network, GitHub unreachable, rate-limited, a garbage
/// body — is swallowed and treated as "no update found". This never shows
/// an error dialog and never blocks anything the app is doing; the request
/// itself carries no auth, no cookies, no body, and nothing about the user
/// or their projects.
enum UpdateChecker {
    static let releaseAPIURL = URL(string: "https://api.github.com/repos/blinbirka/aikon/releases/latest")!
    static let releasePageURL = URL(string: "https://github.com/blinbirka/aikon/releases/latest")!

    private static let checkInterval: TimeInterval = 3 * 24 * 60 * 60

    // MARK: - Scheduling (pure — no clock, no network)

    /// Whether it's time to ask GitHub again: the switch has to be on, and
    /// either there's no record of a previous check or a full day has
    /// passed since one. A pure function of dates so "not more than once a
    /// day" is testable without touching the clock or the network.
    static func shouldCheck(enabled: Bool, lastCheckedAt: Date?, now: Date = Date()) -> Bool {
        guard enabled else { return false }
        guard let lastCheckedAt else { return true }
        return now.timeIntervalSince(lastCheckedAt) >= checkInterval
    }

    // MARK: - Version comparison (pure)

    /// Numeric, per-segment comparison — "0.10.0" is newer than "0.9.0",
    /// which a plain string compare gets backwards ("0.10.0" < "0.9.0"
    /// lexicographically). A leading "v", as GitHub's `tag_name` has it,
    /// doesn't matter either way. Missing trailing segments count as 0, so
    /// "0.2" and "0.2.0" compare equal.
    static func isNewer(_ remote: String, than local: String) -> Bool {
        let r = segments(remote)
        let l = segments(local)
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }

    private static func segments(_ version: String) -> [Int] {
        var v = Substring(version)
        if v.first == "v" || v.first == "V" { v.removeFirst() }
        return v.split(separator: ".").map { Int($0) ?? 0 }
    }

    /// What to show, if anything: `nil` unless the last successful check
    /// found something strictly newer than what's actually running.
    static func availableUpdate(latestKnown: String?, current: String) -> String? {
        guard let latestKnown, isNewer(latestKnown, than: current) else { return nil }
        return latestKnown
    }

    // MARK: - Parsing GitHub's response (pure)

    private struct ReleaseResponse: Decodable {
        let tagName: String
        private enum CodingKeys: String, CodingKey { case tagName = "tag_name" }
    }

    /// `nil` for anything that isn't the shape expected — not JSON, missing
    /// `tag_name`, wrong type — so a broken or unexpected response reads
    /// exactly like "no update found" instead of crashing anything.
    static func latestVersion(fromReleaseJSON data: Data) -> String? {
        guard let response = try? JSONDecoder().decode(ReleaseResponse.self, from: data) else { return nil }
        var tag = Substring(response.tagName)
        if tag.first == "v" || tag.first == "V" { tag.removeFirst() }
        return tag.isEmpty ? nil : String(tag)
    }

    // MARK: - The actual request

    /// One anonymous GET, 10 seconds max, no auth header, no cookies, no
    /// body. Returns the newest tag_name (leading "v" stripped) on success,
    /// `nil` on literally anything else — including a well-formed response
    /// GitHub sent back with an error status.
    static func fetchLatestTag(session: URLSession = UpdateChecker.session) async -> String? {
        var request = URLRequest(url: releaseAPIURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.httpShouldHandleCookies = false
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            return latestVersion(fromReleaseJSON: data)
        } catch {
            return nil
        }
    }

    /// Ephemeral on purpose: nothing about this request should be
    /// remembered between calls — no cookies, no shared cache.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()
}
