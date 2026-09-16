import XCTest
@testable import RatioNative

final class HistoryFormattingTests: XCTestCase {
    func testOverviewLabelUsesTodayOnlyForMatchingRecordedDay() {
        XCTAssertEqual(
            HistoryFormatting.overviewDateLabel(
                for: "2026-09-16",
                today: "2026-09-16"
            ),
            "TODAY"
        )
        XCTAssertEqual(
            HistoryFormatting.overviewDateLabel(
                for: "2026-09-15",
                today: "2026-09-16"
            ),
            "SEP 15"
        )
    }

    func testDetailDateLabelKeepsDateForToday() {
        XCTAssertEqual(HistoryFormatting.dateLabel(for: "2026-09-16"), "SEP 16")
    }
}
