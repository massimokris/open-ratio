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
}
