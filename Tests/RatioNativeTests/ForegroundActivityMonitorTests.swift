import AppKit
import XCTest
import RatioCore
@testable import RatioNative

final class ForegroundActivityMonitorTests: XCTestCase {
    @MainActor
    func testOtherApplicationsKeepTrackingDespiteMatchingNamesOrMissingBundleIdentifiers() async {
        let monitor = ForegroundActivityMonitor(currentBundleIdentifier: nil)
        let ordinaryApplications = [
            ("com.example.settings", "System Settings"),
            ("com.example.finder", "Finder"),
            ("com.example.loginwindow", "loginwindow"),
            ("com.example.ratio", "Ratio Native"),
            ("com.apple.finder.helper", "Finder Helper")
        ]
        var notifiedForeground: NSRunningApplication?
        monitor.onForegroundApplicationChange = { notifiedForeground = $0 }
        for (bundleIdentifier, name) in ordinaryApplications {
            let application = RunningApplication(bundleIdentifier: bundleIdentifier, name: name)
            let observation = monitor.sample(foreground: application, date: Date(timeIntervalSince1970: 0),
                                             uptime: 1000, idleSeconds: 0)
            XCTAssertEqual(observation.source, ActivitySource(id: "app." + bundleIdentifier, name: name))
            XCTAssertTrue(notifiedForeground === application)
        }

        let unbundled = RunningApplication(bundleIdentifier: nil, name: "Local Tool",
                                           bundleURL: URL(fileURLWithPath: "/Applications/Local Tool.app"))
        let observation = monitor.sample(foreground: unbundled, date: Date(timeIntervalSince1970: 0),
                                         uptime: 1000, idleSeconds: 0)
        XCTAssertEqual(observation.source, ActivitySource(id: "app./Applications/Local Tool.app", name: "Local Tool"))
        XCTAssertTrue(notifiedForeground === unbundled)
    }

    @MainActor
    func testSystemAndOwnApplicationsAreExcludedByIdentityAcrossRenamesAndProcesses() async {
        let monitor = ForegroundActivityMonitor(currentBundleIdentifier: "dev.ratio.QA")
        let anotherProcess = ProcessInfo.processInfo.processIdentifier + 1
        let excluded = [
            RunningApplication(bundleIdentifier: "com.apple.systempreferences", name: "Réglages Système"),
            RunningApplication(bundleIdentifier: "com.apple.finder", name: "Renamed Finder"),
            RunningApplication(bundleIdentifier: "com.apple.loginwindow", name: "Login"),
            RunningApplication(bundleIdentifier: "com.rationative.RatioNative", name: "Ratio Copy", processIdentifier: anotherProcess),
            RunningApplication(bundleIdentifier: "dev.ratio.QA", name: "QA Copy", processIdentifier: anotherProcess),
            RunningApplication(bundleIdentifier: nil, name: "Unbundled Ratio", processIdentifier: ProcessInfo.processInfo.processIdentifier)
        ]
        monitor.sourceResolver = { _, fallback in
            XCTFail("Excluded applications must not reach website resolution")
            return fallback
        }
        var foregroundChanges: [NSRunningApplication?] = []
        monitor.onForegroundApplicationChange = { foregroundChanges.append($0) }

        for application in excluded {
            let observation = monitor.sample(foreground: application, date: Date(timeIntervalSince1970: 0),
                                             uptime: 1000, idleSeconds: 0)
            XCTAssertNil(observation.source, application.localizedName ?? "")
        }

        XCTAssertEqual(foregroundChanges.count, excluded.count)
        XCTAssertTrue(foregroundChanges.allSatisfy { $0 == nil })
    }

    @MainActor
    func testExcludedForegroundStopsAccountingAndWebsiteResolutionThenNormalTrackingResumes() async {
        let monitor = ForegroundActivityMonitor()
        let editor = RunningApplication(bundleIdentifier: "com.example.editor", name: "Editor")
        let finder = RunningApplication(bundleIdentifier: "com.apple.finder", name: "Finder")
        let browser = RunningApplication(bundleIdentifier: "com.apple.Safari", name: "Safari")
        let website = ActivitySource(id: "website.example.com", name: "example.com", kind: .website)
        let historicalFinder = ActivitySource(id: "app.com.apple.finder", name: "Finder")
        var ledger = ActivityLedger()
        ledger.record(seconds: 60, source: historicalFinder, day: "2026-09-14")
        ledger.classify(historicalFinder, as: .consume)
        var session = RatioSession(liveLedger: ledger)
        var notifiedForeground: NSRunningApplication?
        monitor.onForegroundApplicationChange = { notifiedForeground = $0 }
        monitor.sourceResolver = { application, fallback in
            XCTAssertNotEqual(application.bundleIdentifier, "com.apple.finder")
            return application.bundleIdentifier == "com.apple.Safari" ? website : fallback
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let origin = Date(timeIntervalSince1970: 1_789_473_600) // 2026-09-15 12:00 UTC.
        func observe(_ second: TimeInterval, _ application: NSRunningApplication) {
            session.observe(monitor.sample(foreground: application,
                                           date: origin.addingTimeInterval(second),
                                           uptime: 1000 + second, idleSeconds: 0), calendar: calendar)
        }

        observe(0, editor)
        observe(4, finder)
        XCTAssertNil(session.activeSource)
        XCTAssertNil(notifiedForeground)
        observe(8, finder)
        observe(10, browser)
        observe(13, browser)

        let today = session.ledger.summary(on: "2026-09-15")
        XCTAssertEqual(today.totalSeconds, 7)
        XCTAssertEqual(today.activities.first { $0.id == "app.com.example.editor" }?.seconds, 4)
        XCTAssertEqual(today.activities.first { $0.id == website.id }?.seconds, 3)
        XCTAssertFalse(today.activities.contains { $0.id == historicalFinder.id })
        XCTAssertEqual(session.activeSource, website)
        XCTAssertEqual(notifiedForeground?.bundleIdentifier, "com.apple.Safari")
        XCTAssertEqual(session.ledger.summary(on: "2026-09-14").totalSeconds, 60)
        XCTAssertEqual(session.ledger.categories[historicalFinder.id], .consume)
    }
}

/// Supplies the native identity boundary without activating real applications.
private final class RunningApplication: NSRunningApplication, @unchecked Sendable {
    private let suppliedBundleIdentifier: String?
    private let suppliedName: String
    private let suppliedProcessIdentifier: pid_t
    private let suppliedBundleURL: URL?

    init(bundleIdentifier: String?, name: String,
         processIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier + 1, bundleURL: URL? = nil) {
        suppliedBundleIdentifier = bundleIdentifier
        suppliedName = name
        suppliedProcessIdentifier = processIdentifier
        suppliedBundleURL = bundleURL
        super.init()
    }

    override var bundleIdentifier: String? { suppliedBundleIdentifier }
    override var localizedName: String? { suppliedName }
    override var processIdentifier: pid_t { suppliedProcessIdentifier }
    override var bundleURL: URL? { suppliedBundleURL }
}
