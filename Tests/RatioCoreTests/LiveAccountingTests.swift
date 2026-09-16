import XCTest
@testable import RatioCore

final class LiveAccountingTests: XCTestCase {
    private let editor = ActivitySource(id: "app.editor", name: "Editor")
    private let browser = ActivitySource(id: "app.browser", name: "Browser")
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private let origin = ISO8601DateFormatter().date(from: "2026-09-15T12:00:00Z")!
    private func observation(_ seconds: Double, source: ActivitySource?, idle: Double = 0) -> ActivityObservation {
        ActivityObservation(date: origin.addingTimeInterval(seconds), uptime: 1000 + seconds,
                            idleSeconds: idle, source: source)
    }

    func testSwitchCreditsOutgoingSourceAndNewSourceStartsUnclassified() {
        var session = RatioSession()
        session.observe(observation(0, source: editor), calendar: utc)
        session.observe(observation(4, source: browser), calendar: utc)
        session.observe(observation(7, source: browser), calendar: utc)
        let summary = session.ledger.summary(on: "2026-09-15")
        XCTAssertEqual(summary.totalSeconds, 7)
        XCTAssertEqual(summary.activities.first { $0.id == editor.id }?.seconds, 4)
        XCTAssertEqual(summary.activities.first { $0.id == browser.id }?.seconds, 3)
        XCTAssertEqual(summary.unclassifiedSeconds, 7)
        XCTAssertNil(summary.createPercentage)
        XCTAssertEqual(session.activeSource, browser)
    }
    func testPauseDemoAndSystemSuspensionReanchorWithoutCreditingHiddenTime() {
        var session = RatioSession()
        session.observe(observation(0, source: editor), calendar: utc)
        session.observe(observation(4, source: editor), calendar: utc)
        session.setPaused(true)
        session.observe(observation(6, source: editor), calendar: utc)
        session.setPaused(false)
        session.observe(observation(9, source: editor), calendar: utc)
        session.observe(observation(11, source: editor), calendar: utc)
        session.enterDemo(day: "2026-09-15")
        session.observe(observation(15, source: browser), calendar: utc)
        session.exitDemo()
        session.observe(observation(18, source: browser), calendar: utc)
        session.observe(observation(20, source: browser), calendar: utc)
        session.setSystemActive(false)
        session.observe(observation(24, source: browser), calendar: utc)
        session.setSystemActive(true)
        session.observe(observation(28, source: browser), calendar: utc)
        session.observe(observation(30, source: browser), calendar: utc)
        let summary = session.ledger.summary(on: "2026-09-15")
        XCTAssertEqual(summary.totalSeconds, 10)
        XCTAssertEqual(summary.activities.first { $0.id == editor.id }?.seconds, 6)
        XCTAssertEqual(summary.activities.first { $0.id == browser.id }?.seconds, 4)
    }

    func testLongGapClockDiscontinuityAndNegativeUptimeReanchorThenResume() {
        var session = RatioSession()
        session.observe(observation(0, source: editor), calendar: utc)
        session.observe(observation(10, source: editor), calendar: utc)
        session.observe(observation(21, source: editor), calendar: utc)
        session.observe(observation(22, source: editor), calendar: utc)
        session.observe(ActivityObservation(date: origin.addingTimeInterval(60), uptime: 1023,
                                            idleSeconds: 0, source: editor), calendar: utc)
        session.observe(ActivityObservation(date: origin.addingTimeInterval(61), uptime: 1024,
                                            idleSeconds: 0, source: editor), calendar: utc)
        session.observe(ActivityObservation(date: origin.addingTimeInterval(62), uptime: 900,
                                            idleSeconds: 0, source: editor), calendar: utc)
        session.observe(ActivityObservation(date: origin.addingTimeInterval(63), uptime: 901,
                                            idleSeconds: 0, source: editor), calendar: utc)
        XCTAssertEqual(session.ledger.summary(on: "2026-09-15").totalSeconds, 13)
    }

    func testFiveMinuteIdleGraceStopsAtCutoffAndResumesAtRecentInput() {
        var session = RatioSession()
        for second in stride(from: 0, through: 290, by: 10) {
            session.observe(observation(Double(second), source: editor, idle: Double(second)), calendar: utc)
        }
        session.observe(observation(298, source: editor, idle: 298), calendar: utc)
        session.observe(observation(304, source: editor, idle: 304), calendar: utc)
        XCTAssertTrue(session.isLiveIdle)
        XCTAssertEqual(session.ledger.summary(on: "2026-09-15").totalSeconds, 300)
        // At 309, the system reports input two seconds ago: only 307–309 counts.
        session.observe(observation(309, source: editor, idle: 2), calendar: utc)
        session.observe(observation(314, source: editor, idle: 7), calendar: utc)
        XCTAssertFalse(session.isLiveIdle)
        XCTAssertEqual(session.ledger.summary(on: "2026-09-15").totalSeconds, 307)
    }

    func testOrdinaryIntervalSplitsAtLocalMidnightAndRetainsAssignedDaysAfterTravel() {
        var session = RatioSession()
        let midnight = ISO8601DateFormatter().date(from: "2026-09-16T00:00:00Z")!
        session.observe(ActivityObservation(date: midnight.addingTimeInterval(-2), uptime: 100,
                                            idleSeconds: 0, source: editor), calendar: utc)
        session.observe(ActivityObservation(date: midnight.addingTimeInterval(4), uptime: 106,
                                            idleSeconds: 0, source: editor), calendar: utc)
        XCTAssertEqual(session.ledger.summary(on: "2026-09-15").totalSeconds, 2)
        XCTAssertEqual(session.ledger.summary(on: "2026-09-16").totalSeconds, 4)
        var western = utc
        western.timeZone = TimeZone(secondsFromGMT: -7 * 3600)!
        session.observe(ActivityObservation(date: midnight.addingTimeInterval(6), uptime: 108,
                                            idleSeconds: 0, source: editor), calendar: western)
        XCTAssertEqual(session.ledger.summary(on: "2026-09-15").totalSeconds, 4)
        XCTAssertEqual(session.ledger.summary(on: "2026-09-16").totalSeconds, 4)
    }

    func testResetTodayRetainsPastDaysAndCategoriesAndUndoMergesSubsequentTime() {
        var session = RatioSession()
        session.recordLive(seconds: 30, source: editor, day: "2026-09-14")
        session.recordLive(seconds: 20, source: editor, day: "2026-09-15")
        session.classify(editor, as: .create)
        session.resetDay("2026-09-15")
        XCTAssertEqual(session.ledger.summary(on: "2026-09-15").totalSeconds, 0)
        XCTAssertEqual(session.ledger.summary(on: "2026-09-14").totalSeconds, 30)
        XCTAssertEqual(session.ledger.categories[editor.id], .create)
        XCTAssertTrue(session.canUndoReset)
        session.recordLive(seconds: 3, source: editor, day: "2026-09-15")
        session.recordLive(seconds: 2, source: browser, day: "2026-09-15")
        session.undoReset()
        let today = session.ledger.summary(on: "2026-09-15")
        XCTAssertEqual(today.totalSeconds, 25)
        XCTAssertEqual(today.createSeconds, 23)
        XCTAssertEqual(today.unclassifiedSeconds, 2)
        XCTAssertFalse(session.canUndoReset)
        session.undoReset()
        XCTAssertEqual(session.ledger.summary(on: "2026-09-15").totalSeconds, 25)
        session.enterDemo(day: "2026-09-15")
        session.resetDay("2026-09-15")
        session.exitDemo()
        XCTAssertEqual(session.ledger.summary(on: "2026-09-15").totalSeconds, 25)
    }

    func testDeletingActiveSourceSuppressesItUntilAnotherSourceBecomesActive() throws {
        let today = "2026-09-15"
        var session = RatioSession()
        session.classify(editor, as: .create)
        session.observe(observation(0, source: editor), calendar: utc)
        session.observe(observation(4, source: editor), calendar: utc)

        let deletion = try XCTUnwrap(session.deleteActivity(editor, on: today))
        session.observe(observation(6, source: editor), calendar: utc)
        session.observe(observation(8, source: browser), calendar: utc)
        session.observe(observation(11, source: browser), calendar: utc)
        session.observe(observation(13, source: editor), calendar: utc)
        session.observe(observation(17, source: editor), calendar: utc)

        XCTAssertEqual(deletion.activity.seconds, 4)
        XCTAssertEqual(session.ledger.summary(on: today).activities.first { $0.id == browser.id }?.seconds, 5)
        XCTAssertEqual(session.ledger.summary(on: today).activities.first { $0.id == editor.id }?.seconds, 4)
        XCTAssertEqual(session.ledger.categories[editor.id], .create)
    }

    func testUndoWhileDeletedSourceRemainsActiveDoesNotCreditSuppressedTime() throws {
        let today = "2026-09-15"
        var session = RatioSession()
        session.observe(observation(0, source: editor), calendar: utc)
        session.observe(observation(4, source: editor), calendar: utc)
        let deletion = try XCTUnwrap(session.deleteActivity(editor, on: today))
        XCTAssertTrue(session.isActiveSourceSuppressed)
        session.observe(observation(6, source: editor), calendar: utc)

        session.undoDelete(deletion)
        XCTAssertTrue(session.isActiveSourceSuppressed)
        session.observe(observation(8, source: editor), calendar: utc)
        XCTAssertEqual(session.ledger.summary(on: today).totalSeconds, 4)

        session.observe(observation(10, source: browser), calendar: utc)
        XCTAssertFalse(session.isActiveSourceSuppressed)
        session.observe(observation(12, source: editor), calendar: utc)
        session.observe(observation(14, source: editor), calendar: utc)
        XCTAssertEqual(session.ledger.summary(on: today).activities.first { $0.id == editor.id }?.seconds, 6)
        XCTAssertEqual(session.ledger.summary(on: today).activities.first { $0.id == browser.id }?.seconds, 2)
    }

}
