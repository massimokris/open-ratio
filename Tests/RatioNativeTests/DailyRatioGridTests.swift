import XCTest
import RatioCore
@testable import RatioNative

final class DailyRatioGridTests: XCTestCase {
    func testBuildsTwentySixSundayFirstWeeksAcrossYearBoundaryWithFutureSlotsBlank() {
        let grid = DailyRatioGrid(ledger: ActivityLedger(), today: "2026-01-02")

        XCTAssertEqual(grid.weeks.count, 26)
        XCTAssertTrue(grid.weeks.allSatisfy { $0.slots.count == 7 })
        XCTAssertEqual(grid.weeks.first?.slots.map(\.dayIdentifier), [
            "2025-07-06", "2025-07-07", "2025-07-08", "2025-07-09",
            "2025-07-10", "2025-07-11", "2025-07-12"
        ])
        XCTAssertEqual(grid.weeks.last?.slots.map(\.dayIdentifier), [
            "2025-12-28", "2025-12-29", "2025-12-30", "2025-12-31",
            "2026-01-01", "2026-01-02", "2026-01-03"
        ])
        XCTAssertNotNil(grid.weeks.last?.slots[5].day)
        XCTAssertNil(grid.weeks.last?.slots[6].day)
    }

    func testCreatingDominanceUsesClassifiedShareForLinearIntensity() throws {
        let createSource = ActivitySource(id: "app.create", name: "Create")
        let consumeSource = ActivitySource(id: "app.consume", name: "Consume")
        var ledger = ActivityLedger()
        ledger.classify(createSource, as: .create)
        ledger.classify(consumeSource, as: .consume)
        ledger.record(seconds: 70, source: createSource, day: "2026-09-15")
        ledger.record(seconds: 30, source: consumeSource, day: "2026-09-15")

        let grid = DailyRatioGrid(ledger: ledger, today: "2026-09-15")
        let day = try XCTUnwrap(
            grid.weeks.flatMap(\.slots).first { $0.dayIdentifier == "2026-09-15" }?.day
        )

        XCTAssertEqual(day.presentation, .dominant(category: .create, percentage: 70))
        XCTAssertEqual(day.opacity, 0.75, accuracy: 0.000_001)
    }

    func testFormatsDominantTieAndNoRatioTooltipsFromUnderlyingRatio() throws {
        let creating = try gridDay(create: 72, consume: 28)
        let consuming = try gridDay(create: 14, consume: 86, dayIdentifier: "2026-09-14")
        let almostTie = try gridDay(create: 50.1, consume: 49.9)
        let tie = try gridDay(create: 50, consume: 50)
        let capped = try gridDay(create: 95, consume: 5)
        let complete = try gridDay(create: 100)
        let unclassifiedOnly = try gridDay(unclassified: 100)
        let noActivity = try gridDay()

        XCTAssertEqual(creating.tooltip, "72% Creating on Sep 15")
        XCTAssertEqual(consuming.tooltip, "86% Consuming on Sep 14")
        XCTAssertEqual(almostTie.tooltip, "50% Creating on Sep 15")
        XCTAssertEqual(tie.tooltip, "50% Creating / 50% Consuming on Sep 15")
        XCTAssertEqual(capped.tooltip, "95% Creating on Sep 15")
        XCTAssertEqual(complete.tooltip, "100% Creating on Sep 15")
        XCTAssertEqual(unclassifiedOnly.tooltip, "No ratio on Sep 15")
        XCTAssertEqual(noActivity.tooltip, "No ratio on Sep 15")
        XCTAssertEqual(tie.presentation, .tie)
        XCTAssertEqual(tie.opacity, 0.25)
        XCTAssertEqual(unclassifiedOnly.presentation, .noRatio)
        XCTAssertEqual(noActivity.presentation, .noRatio)
    }

    func testSpecifiedDominantSharesUseContinuousCappedIntensity() throws {
        let examples: [(create: TimeInterval, consume: TimeInterval, category: ActivityCategory,
                        percentage: Double, opacity: Double)] = [
            (50.1, 49.9, .create, 50.1, 0.2525),
            (60, 40, .create, 60, 0.5),
            (80, 20, .create, 80, 1),
            (95, 5, .create, 95, 1),
            (100, 0, .create, 100, 1),
            (30, 70, .consume, 70, 0.75),
            (14, 86, .consume, 86, 1)
        ]

        for example in examples {
            let day = try gridDay(create: example.create, consume: example.consume)
            guard case let .dominant(category, percentage) = day.presentation else {
                return XCTFail("Expected a dominant category for \(example.create)/\(example.consume)")
            }
            XCTAssertEqual(category, example.category)
            XCTAssertEqual(percentage, example.percentage, accuracy: 0.000_001)
            XCTAssertEqual(day.opacity, example.opacity, accuracy: 0.000_001)
        }
    }

    func testIntensityDependsOnRatioNotDurationOrUnclassifiedTime() throws {
        let short = try gridDay(create: 7, consume: 3)
        let long = try gridDay(create: 7_000, consume: 3_000)
        let withUnclassified = try gridDay(create: 7, consume: 3, unclassified: 10_000)

        XCTAssertEqual([short.presentation, long.presentation, withUnclassified.presentation], [
            .dominant(category: .create, percentage: 70),
            .dominant(category: .create, percentage: 70),
            .dominant(category: .create, percentage: 70)
        ])
        XCTAssertEqual([short.opacity, long.opacity, withUnclassified.opacity], [0.75, 0.75, 0.75])
    }

    func testTooltipPlacementCentersAboveWhenPossibleAndStaysInsidePanelEdges() {
        let bounds = CGRect(x: 0, y: 0, width: 360, height: 220)
        let tooltipSize = CGSize(width: 200, height: 22)

        let middle = DailyRatioTooltipPlacement.center(
            for: CGRect(x: 175, y: 48, width: 10, height: 10),
            tooltipSize: tooltipSize,
            within: bounds
        )
        let firstTop = DailyRatioTooltipPlacement.center(
            for: CGRect(x: 25, y: 16, width: 10, height: 10),
            tooltipSize: tooltipSize,
            within: bounds
        )
        let lastTop = DailyRatioTooltipPlacement.center(
            for: CGRect(x: 325, y: 16, width: 10, height: 10),
            tooltipSize: tooltipSize,
            within: bounds
        )

        XCTAssertEqual(middle, CGPoint(x: 180, y: 33))
        XCTAssertLessThanOrEqual(tooltipFrame(center: middle, size: tooltipSize).maxY, 48)
        XCTAssertGreaterThanOrEqual(tooltipFrame(center: firstTop, size: tooltipSize).minX, bounds.minX)
        XCTAssertGreaterThanOrEqual(tooltipFrame(center: firstTop, size: tooltipSize).minY, bounds.minY)
        XCTAssertGreaterThanOrEqual(tooltipFrame(center: firstTop, size: tooltipSize).minY, 26)
        XCTAssertLessThanOrEqual(tooltipFrame(center: lastTop, size: tooltipSize).maxX, bounds.maxX)
        XCTAssertGreaterThanOrEqual(tooltipFrame(center: lastTop, size: tooltipSize).minY, bounds.minY)
        XCTAssertGreaterThanOrEqual(tooltipFrame(center: lastTop, size: tooltipSize).minY, 26)
    }

    func testGridGeometryFitsTheCompactPanel() {
        XCTAssertEqual(DailyRatioGridMetrics.width, 310)
        XCTAssertEqual(DailyRatioGridMetrics.height, 82)
        XCTAssertEqual(DailyRatioGridMetrics.width + 32, 342)
        XCTAssertLessThanOrEqual(DailyRatioGridMetrics.width + 32, 360)
    }

    func testReclassificationRebuildsHistoricalRatioWithoutChangingTrackedTime() throws {
        let first = ActivitySource(id: "app.first", name: "First")
        let second = ActivitySource(id: "app.second", name: "Second")
        var ledger = ActivityLedger()
        ledger.record(seconds: 70, source: first, day: "2025-12-31")
        ledger.record(seconds: 30, source: second, day: "2025-12-31")
        ledger.classify(first, as: .create)
        ledger.classify(second, as: .consume)

        let before = try gridDay(in: ledger, on: "2025-12-31", today: "2026-01-02")
        let trackedSeconds = ledger.summary(on: "2025-12-31").totalSeconds
        ledger.classify(first, as: .consume)
        let after = try gridDay(in: ledger, on: "2025-12-31", today: "2026-01-02")

        XCTAssertEqual(before.presentation, .dominant(category: .create, percentage: 70))
        XCTAssertEqual(after.presentation, .dominant(category: .consume, percentage: 100))
        XCTAssertEqual(ledger.summary(on: "2025-12-31").totalSeconds, trackedSeconds)
    }

    func testGridUsesOnlyTheSessionLedgerForTheCurrentMode() throws {
        let source = ActivitySource(id: "app.shared", name: "Shared")
        var liveLedger = ActivityLedger()
        liveLedger.record(seconds: 100, source: source, day: "2026-09-15")
        liveLedger.classify(source, as: .create)
        var demoLedger = ActivityLedger()
        demoLedger.record(seconds: 100, source: source, day: "2026-09-15")
        demoLedger.classify(source, as: .consume)
        var session = RatioSession(liveLedger: liveLedger)
        session.enterDemo(ledger: demoLedger, activeSource: source)

        let demoDay = try gridDay(in: session.ledger, on: "2026-09-15", today: "2026-09-15")
        session.exitDemo()
        let liveDay = try gridDay(in: session.ledger, on: "2026-09-15", today: "2026-09-15")

        XCTAssertEqual(demoDay.presentation, .dominant(category: .consume, percentage: 100))
        XCTAssertEqual(liveDay.presentation, .dominant(category: .create, percentage: 100))
        XCTAssertEqual(session.liveLedger, liveLedger)
    }

    private func gridDay(
        create: TimeInterval = 0,
        consume: TimeInterval = 0,
        unclassified: TimeInterval = 0,
        dayIdentifier: String = "2026-09-15"
    ) throws -> DailyRatioDay {
        let createSource = ActivitySource(id: "app.create", name: "Create")
        let consumeSource = ActivitySource(id: "app.consume", name: "Consume")
        let unclassifiedSource = ActivitySource(id: "app.unclassified", name: "Unclassified")
        var ledger = ActivityLedger()
        ledger.classify(createSource, as: .create)
        ledger.classify(consumeSource, as: .consume)
        ledger.record(seconds: create, source: createSource, day: dayIdentifier)
        ledger.record(seconds: consume, source: consumeSource, day: dayIdentifier)
        ledger.record(seconds: unclassified, source: unclassifiedSource, day: dayIdentifier)
        return try gridDay(in: ledger, on: dayIdentifier, today: dayIdentifier)
    }

    private func gridDay(in ledger: ActivityLedger, on dayIdentifier: String, today: String) throws -> DailyRatioDay {
        let grid = DailyRatioGrid(ledger: ledger, today: today)
        return try XCTUnwrap(
            grid.weeks.flatMap(\.slots).first { $0.dayIdentifier == dayIdentifier }?.day
        )
    }

    private func tooltipFrame(center: CGPoint, size: CGSize) -> CGRect {
        CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
