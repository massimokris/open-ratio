import XCTest
@testable import RatioCore

final class ActivityLedgerTests: XCTestCase {
    func testEmptyDayHasNoInventedRatioOrActivity() {
        let ledger = ActivityLedger()
        let summary = ledger.summary(on: "2026-09-15")
        XCTAssertEqual(summary.totalSeconds, 0)
        XCTAssertNil(summary.createPercentage)
        XCTAssertTrue(summary.activities.isEmpty)
    }
    func testClassificationRevisesRetainedTimeWithoutLosingUnclassifiedTime() {
        var ledger = ActivityLedger()
        let editor = ActivitySource(id: "app.editor", name: "Editor")
        let video = ActivitySource(id: "web.video.test", name: "video.test", kind: .website)
        let unknown = ActivitySource(id: "app.chat", name: "Chat")
        ledger.record(seconds: 3600, source: editor, day: "2026-09-14")
        ledger.record(seconds: 1800, source: video, day: "2026-09-14")
        ledger.record(seconds: 900, source: unknown, day: "2026-09-14")
        XCTAssertNil(ledger.summary(on: "2026-09-14").createPercentage)
        ledger.classify(editor, as: .create)
        ledger.classify(video, as: .consume)
        let summary = ledger.summary(on: "2026-09-14")
        XCTAssertEqual(summary.totalSeconds, 6300)
        XCTAssertEqual(summary.unclassifiedSeconds, 900)
        XCTAssertEqual(summary.createPercentage ?? -1, 66.6666667, accuracy: 0.00001)
        ledger.classify(video, as: .create)
        XCTAssertEqual(ledger.summary(on: "2026-09-14").createPercentage, 100)
        ledger.classify(editor, as: nil)
        XCTAssertEqual(ledger.summary(on: "2026-09-14").unclassifiedSeconds, 4500)
        XCTAssertEqual(ledger.summary(on: "2026-09-14").totalSeconds, 6300)
    }

    func testRemovingOneSourceFromDayRetainsItsCategoryAndEarlierActivity() throws {
        let earlierDay = "2026-09-14"
        let today = "2026-09-15"
        let editor = ActivitySource(id: "app.editor", name: "Editor")
        let video = ActivitySource(id: "web.video.test", name: "video.test", kind: .website)
        var ledger = ActivityLedger()
        ledger.classify(editor, as: .create)
        ledger.classify(video, as: .consume)
        ledger.record(seconds: 30, source: editor, day: earlierDay)
        ledger.record(seconds: 60, source: editor, day: today)
        ledger.record(seconds: 40, source: video, day: today)

        let removed = try XCTUnwrap(ledger.removeActivity(for: editor, on: today))

        XCTAssertEqual(removed.source, editor)
        XCTAssertEqual(removed.seconds, 60)
        XCTAssertEqual(ledger.summary(on: today).totalSeconds, 40)
        XCTAssertEqual(ledger.summary(on: today).createPercentage, 0)
        XCTAssertEqual(ledger.summary(on: earlierDay).totalSeconds, 30)
        XCTAssertEqual(ledger.categories[editor.id], .create)
    }

    func testRemovingWebsiteAndUnclassifiedSourcesRecalculatesRatioAndUnclassifiedTime() throws {
        let today = "2026-09-15"
        let editor = ActivitySource(id: "app.editor", name: "Editor")
        let video = ActivitySource(id: "web.video.test", name: "video.test", kind: .website)
        let chat = ActivitySource(id: "app.chat", name: "Chat")
        var ledger = ActivityLedger()
        ledger.classify(editor, as: .create)
        ledger.classify(video, as: .consume)
        ledger.record(seconds: 60, source: editor, day: today)
        ledger.record(seconds: 30, source: video, day: today)
        ledger.record(seconds: 10, source: chat, day: today)

        XCTAssertNotNil(ledger.removeActivity(for: video, on: today))
        XCTAssertEqual(ledger.summary(on: today).totalSeconds, 70)
        XCTAssertEqual(ledger.summary(on: today).createPercentage, 100)
        XCTAssertEqual(ledger.summary(on: today).unclassifiedSeconds, 10)
        XCTAssertEqual(ledger.summary(on: today).activities.filter { $0.category == nil }.count, 1)
        XCTAssertEqual(ledger.categories[video.id], .consume)

        XCTAssertNotNil(ledger.removeActivity(for: chat, on: today))
        XCTAssertEqual(ledger.summary(on: today).totalSeconds, 60)
        XCTAssertEqual(ledger.summary(on: today).unclassifiedSeconds, 0)
        XCTAssertEqual(ledger.summary(on: today).activities.filter { $0.category == nil }.count, 0)
    }
}
