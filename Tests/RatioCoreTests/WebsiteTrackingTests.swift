import XCTest
@testable import RatioCore

final class WebsiteTrackingTests: XCTestCase {
    private let browser = BrowserIdentity(bundleIdentifier: "com.apple.Safari", processIdentifier: 42)
    private let application = ActivitySource(id: "app.com.apple.Safari", name: "Safari")
    func testHTTPHostDropsPrivateURLDetailsAndKeepsSubdomains() {
        let host = WebsiteHost(urlString: "HTTPS://WWW.Docs.Example.COM:443/private/path?search=secret#fragment")
        XCTAssertEqual(host?.value, "docs.example.com")
        XCTAssertEqual(host?.source, ActivitySource(id: "website.docs.example.com", name: "docs.example.com", kind: .website))
        XCTAssertEqual(WebsiteHost(urlString: "http://www.example.com")?.value, "example.com")
        XCTAssertEqual(WebsiteHost(urlString: "https://mail.example.com/inbox")?.value, "mail.example.com")
    }

    func testUnsupportedAndMalformedURLsHaveNoWebsiteSource() {
        for url in ["", "example.com/private", "about:blank", "chrome://settings", "file:///private/note.txt",
                    "ftp://example.com/file", "https:///missing-host", "https://www.",
                    "https://bad%2Fhost.example/path", "https://bad%20host.example/path"] {
            XCTAssertNil(WebsiteHost(urlString: url), "Unexpected host for an unsupported input")
        }
        XCTAssertEqual(WebsiteHost(urlString: "https://name:secret@EXAMPLE.com/private")?.value, "example.com")
    }

    func testQueriesRequirePerBrowserOptInAndRemainSingleFlight() throws {
        var tracking = WebsiteTrackingPolicy()
        tracking.setForeground(browser)
        XCTAssertNil(tracking.beginQuery(at: 0))
        XCTAssertEqual(tracking.source(fallingBackTo: application, at: 0), application)
        tracking.setEnabled(true, for: browser.bundleIdentifier)
        let request = try XCTUnwrap(tracking.beginQuery(at: 1))
        XCTAssertNil(tracking.beginQuery(at: 2))
        XCTAssertEqual(tracking.source(fallingBackTo: application, at: 2), application)
        let host = try XCTUnwrap(WebsiteHost(urlString: "https://docs.example.com/private"))
        XCTAssertTrue(tracking.complete(request, with: .host(host), at: 2))
        XCTAssertEqual(tracking.source(fallingBackTo: application, at: 2), host.source)
        XCTAssertEqual(tracking.status(for: browser.bundleIdentifier), .tracking)
    }

    func testForegroundAndOptInChangesDiscardLateResultsAndCachedHosts() throws {
        let host = try XCTUnwrap(WebsiteHost(urlString: "https://docs.example.com"))
        var tracking = WebsiteTrackingPolicy(enabledBrowsers: [browser.bundleIdentifier])
        tracking.setForeground(browser)
        let beforeSwitch = try XCTUnwrap(tracking.beginQuery(at: 0))
        tracking.setForeground(nil)
        tracking.setForeground(browser)
        XCTAssertNil(tracking.beginQuery(at: 1), "An invalidated native query must still finish before another starts")
        XCTAssertFalse(tracking.complete(beforeSwitch, with: .host(host), at: 1))
        XCTAssertEqual(tracking.source(fallingBackTo: application, at: 1), application)
        let beforeDisable = try XCTUnwrap(tracking.beginQuery(at: 2))
        tracking.setEnabled(false, for: browser.bundleIdentifier)
        tracking.setEnabled(true, for: browser.bundleIdentifier)
        XCTAssertFalse(tracking.complete(beforeDisable, with: .host(host), at: 3))
        let current = try XCTUnwrap(tracking.beginQuery(at: 4))
        XCTAssertTrue(tracking.complete(current, with: .host(host), at: 4))
        XCTAssertEqual(tracking.source(fallingBackTo: application, at: 4), host.source)
        tracking.setForeground(BrowserIdentity(bundleIdentifier: browser.bundleIdentifier, processIdentifier: 99))
        XCTAssertEqual(tracking.source(fallingBackTo: application, at: 5), application)
        let restarted = try XCTUnwrap(tracking.beginQuery(at: 5))
        XCTAssertFalse(tracking.complete(current, with: .host(host), at: 5))
        XCTAssertTrue(tracking.complete(restarted, with: .unavailable, at: 5))
    }

    func testFailuresAndExpiredHostsFallBackWithoutRepeatedPermissionRequests() throws {
        let host = try XCTUnwrap(WebsiteHost(urlString: "https://example.com"))
        var tracking = WebsiteTrackingPolicy(enabledBrowsers: [browser.bundleIdentifier])
        tracking.setForeground(browser)
        let first = try XCTUnwrap(tracking.beginQuery(at: 0))
        tracking.complete(first, with: .host(host), at: 0)
        XCTAssertNil(tracking.beginQuery(at: 0.5), "Polling is at most once per second")
        XCTAssertEqual(tracking.source(fallingBackTo: application, at: 4), application)
        for (index, result) in [WebsiteCaptureResult.timedOut, .unavailable, .unsupportedURL, .denied].enumerated() {
            let time = Double(index + 1) * 20
            let request = try XCTUnwrap(tracking.beginQuery(at: time))
            tracking.complete(request, with: result, at: time)
            XCTAssertEqual(tracking.source(fallingBackTo: application, at: time), application)
        }
        XCTAssertEqual(tracking.status(for: browser.bundleIdentifier), .denied)
        XCTAssertNil(tracking.beginQuery(at: 1000))
        tracking.setForeground(nil)
        tracking.setForeground(browser)
        XCTAssertNil(tracking.beginQuery(at: 1001), "Returning to the browser must not repeat a denied request")
        tracking.retry(browser.bundleIdentifier)
        let retry = try XCTUnwrap(tracking.beginQuery(at: 1002))
        tracking.complete(retry, with: .host(host), at: 1002)
        XCTAssertEqual(tracking.source(fallingBackTo: application, at: 1002), host.source)
        tracking.setEnabled(false, for: browser.bundleIdentifier)
        XCTAssertEqual(tracking.source(fallingBackTo: application, at: 1003), application)
        XCTAssertEqual(tracking.status(for: browser.bundleIdentifier), .disabled)
    }

    func testWebsiteTransitionsKeepIndependentCategoriesAndHostOnlyPersistence() throws {
        let host = try XCTUnwrap(WebsiteHost(urlString: "https://www.example.com/private?q=secret"))
        var tracking = WebsiteTrackingPolicy(enabledBrowsers: [browser.bundleIdentifier])
        tracking.setForeground(browser)
        var session = RatioSession()
        session.classify(application, as: .create)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let origin = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-15T12:00:00Z"))
        func observation(_ seconds: Double) -> ActivityObservation {
            ActivityObservation(date: origin.addingTimeInterval(seconds), uptime: seconds,
                                idleSeconds: 0, source: tracking.source(fallingBackTo: application, at: seconds))
        }
        session.observe(observation(0), calendar: calendar)
        let first = try XCTUnwrap(tracking.beginQuery(at: 1))
        tracking.complete(first, with: .host(host), at: 2)
        session.observe(observation(2), calendar: calendar)
        let second = try XCTUnwrap(tracking.beginQuery(at: 3))
        tracking.complete(second, with: .denied, at: 5)
        session.observe(observation(5), calendar: calendar)
        session.observe(observation(7), calendar: calendar)
        let before = session.ledger.summary(on: "2026-09-15")
        XCTAssertEqual(before.totalSeconds, 7)
        XCTAssertEqual(before.createSeconds, 4)
        XCTAssertEqual(before.unclassifiedSeconds, 3)
        XCTAssertNil(session.ledger.categories[host.source.id])
        session.classify(host.source, as: .consume)
        XCTAssertEqual(session.ledger.summary(on: "2026-09-15").consumeSeconds, 3)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ActivityStore(directory: directory)
        try store.save(session.liveLedger)
        let reloaded = try store.load().ledger
        XCTAssertEqual(reloaded.sources[host.source.id], ActivitySource(id: "website.example.com", name: "example.com", kind: .website))
        XCTAssertEqual(reloaded.categories[host.source.id], .consume)
        XCTAssertEqual(reloaded.categories[application.id], .create)
    }

    func testDeadlineFallsBackWhileAnUnansweredPermissionDialogKeepsTheQuerySingleFlight() throws {
        var tracking = WebsiteTrackingPolicy(enabledBrowsers: [browser.bundleIdentifier])
        tracking.setForeground(browser)
        let request = try XCTUnwrap(tracking.beginQuery(at: 0))
        XCTAssertTrue(tracking.timeout(request, at: 3))
        XCTAssertEqual(tracking.status(for: browser.bundleIdentifier), .timedOut)
        XCTAssertEqual(tracking.source(fallingBackTo: application, at: 3), application)
        XCTAssertNil(tracking.beginQuery(at: 100))
        let host = try XCTUnwrap(WebsiteHost(urlString: "https://example.com"))
        XCTAssertFalse(tracking.complete(request, with: .host(host), at: 100))
        XCTAssertEqual(tracking.source(fallingBackTo: application, at: 100), application)
        XCTAssertNotNil(tracking.beginQuery(at: 101))
    }
}
