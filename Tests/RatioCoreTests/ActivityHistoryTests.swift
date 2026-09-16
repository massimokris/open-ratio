import XCTest
@testable import RatioCore

final class ActivityHistoryTests: XCTestCase {
    func testExportQuotesNamesContainingOnlyLineBreaks() {
        var ledger = ActivityLedger()
        let source = ActivitySource(id: "app.editor", name: "Line one\r\nLine two")
        ledger.record(seconds: 1, source: source, day: "2026-09-15")
        XCTAssertEqual(ledger.activityCSV(), "date,source_type,source_id,name,category,seconds\r\n"
            + "2026-09-15,application,app.editor,\"Line one\r\nLine two\",unclassified,1.0\r\n")
    }

    func testEmptyAndUnclassifiedHistoryExportWithoutInventedRatio() {
        var ledger = ActivityLedger()
        XCTAssertEqual(ledger.activityCSV(), "date,source_type,source_id,name,category,seconds\r\n")
        XCTAssertTrue(ledger.history.isEmpty)
        let source = ActivitySource(id: "app.notes", name: "Notes")
        ledger.record(seconds: 30, source: source, day: "2026-09-14")
        ledger.record(seconds: 15, source: source, day: "2026-09-15")
        XCTAssertEqual(ledger.history.map(\.day), ["2026-09-15", "2026-09-14"])
        XCTAssertNil(ledger.history.first?.createPercentage)
        XCTAssertEqual(ledger.history.last?.unclassifiedSeconds, 30)
        XCTAssertEqual(ledger.activityCSV(), "date,source_type,source_id,name,category,seconds\r\n"
            + "2026-09-15,application,app.notes,Notes,unclassified,15.0\r\n"
            + "2026-09-14,application,app.notes,Notes,unclassified,30.0\r\n")
    }

    func testDemoProvidesRetainedDaysAndResetRestoresFictionalHistoryOnly() throws {
        let source = ActivitySource(id: "app.real", name: "Real editor")
        var session = RatioSession()
        session.recordLive(seconds: 90, source: source, day: "2026-09-13")
        session.classify(source, as: .create)
        session.setPaused(true)
        let realHistory = session.ledger
        session.enterDemo(day: "2026-01-01")

        let demoHistory = session.ledger.history
        XCTAssertEqual(demoHistory.count, 30)
        XCTAssertEqual(demoHistory.first?.day, "2026-01-01")
        XCTAssertEqual(demoHistory.last?.day, "2025-12-03")
        let demoPercentages = demoHistory.compactMap(\.createPercentage)
        XCTAssertEqual(demoPercentages.count, 30)
        XCTAssertTrue(demoPercentages.contains { $0 > 50 && $0 < 80 })
        XCTAssertTrue(demoPercentages.contains { $0 >= 80 })
        XCTAssertTrue(demoPercentages.contains { $0 < 50 && $0 > 20 })
        XCTAssertTrue(demoPercentages.contains { $0 <= 20 })
        XCTAssertTrue(demoPercentages.contains { abs($0 - 50) < 0.000_001 })
        XCTAssertEqual(session.ledger.summary(on: "2025-12-31").createPercentage ?? -1, 70, accuracy: 0.000_001)
        XCTAssertEqual(session.ledger.summary(on: "2025-12-30").createPercentage ?? -1, 30, accuracy: 0.000_001)
        XCTAssertEqual(session.ledger.summary(on: "2025-12-23").createPercentage ?? -1, 50, accuracy: 0.000_001)
        XCTAssertFalse(session.ledger.activityCSV().contains("app.real"))
        let demo = session.ledger
        let figma = try XCTUnwrap(session.availableDemoSources.first { $0.id == "demo.figma" })
        let createBeforeReclassification = session.ledger.summary(on: "2025-12-31").createSeconds
        session.classify(figma, as: .consume)
        XCTAssertLessThan(
            session.ledger.summary(on: "2025-12-31").createSeconds,
            createBeforeReclassification
        )
        session.resetDemo(day: "2026-01-01")
        XCTAssertEqual(session.ledger, demo)
        session.exitDemo()
        XCTAssertEqual(session.ledger, realHistory)
        XCTAssertEqual(session.ledger.activityCSV(), "date,source_type,source_id,name,category,seconds\r\n"
            + "2026-09-13,application,app.real,Real editor,create,90.0\r\n")
        XCTAssertTrue(session.isPaused)
        XCTAssertEqual(session.activeSource, source)
    }

    func testDemoThirtyDayHistoryRemainsContiguousAcrossLeapDay() {
        let history = DemoData.ledger(day: "2024-03-01").history.map(\.day)

        XCTAssertEqual(history.count, 30)
        XCTAssertEqual(history.first, "2024-03-01")
        XCTAssertEqual(history.dropFirst().first, "2024-02-29")
        XCTAssertEqual(history.last, "2024-02-01")
    }

    func testExportEscapesSourceTextAndUsesCurrentCategoryForRetainedDates() {
        var ledger = ActivityLedger()
        let source = ActivitySource(id: "site,one", name: "A \"quoted\"\r\nname", kind: .website)
        ledger.record(seconds: 12.5, source: source, day: "2026-09-14")
        ledger.record(seconds: 60, source: source, day: "2026-09-15")
        ledger.classify(source, as: .create)
        ledger.classify(source, as: .consume)

        XCTAssertEqual(ledger.activityCSV(), "date,source_type,source_id,name,category,seconds\r\n"
            + "2026-09-15,website,\"site,one\",\"A \"\"quoted\"\"\r\nname\",consume,60.0\r\n"
            + "2026-09-14,website,\"site,one\",\"A \"\"quoted\"\"\r\nname\",consume,12.5\r\n")
    }
}
