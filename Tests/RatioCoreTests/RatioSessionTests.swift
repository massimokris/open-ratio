import XCTest
@testable import RatioCore

final class RatioSessionTests: XCTestCase {
    func testDemoClassificationPauseAndResetLeaveLiveDataAndPauseUntouched() {
        let day = "2026-09-15"
        let realSource = ActivitySource(id: "app.real", name: "Real work")
        var session = RatioSession()
        session.recordLive(seconds: 600, source: realSource, day: day)
        session.classify(realSource, as: .create)
        session.setPaused(true)
        let savedLive = session.liveLedger
        session.enterDemo(day: day)
        XCTAssertFalse(session.isPaused)
        let demoSource = session.availableDemoSources[0]
        session.selectDemoSource(demoSource)
        let before = session.ledger.summary(on: day).totalSeconds
        session.advanceDemo(seconds: 30, day: day)
        XCTAssertEqual(session.ledger.summary(on: day).totalSeconds, before + 30)
        session.classify(demoSource, as: .consume)
        XCTAssertEqual(session.ledger.categories[demoSource.id], .consume)
        session.setPaused(true)
        session.advanceDemo(seconds: 30, day: day)
        XCTAssertEqual(session.ledger.summary(on: day).totalSeconds, before + 30)
        session.recordLive(seconds: 900, source: realSource, day: day)
        session.resetDemo(day: day)
        XCTAssertEqual(session.liveLedger, savedLive)
        session.exitDemo()
        XCTAssertTrue(session.isPaused)
        XCTAssertEqual(session.ledger, savedLive)
        XCTAssertEqual(session.ledger.summary(on: day).totalSeconds, 600)
    }
    func testRunningLiveActivityAndCategoriesSurviveDemoEntryAndExit() {
        let day = "2026-09-15"
        let editor = ActivitySource(id: "app.editor", name: "Editor")
        var session = RatioSession()
        session.recordLive(seconds: 120, source: editor, day: day)
        session.classify(editor, as: .create)
        let original = session.liveLedger
        session.enterDemo(day: day)
        session.recordLive(seconds: 400, source: editor, day: day)
        session.classify(editor, as: .consume)
        session.setPaused(true)
        session.exitDemo()
        XCTAssertFalse(session.isPaused)
        XCTAssertEqual(session.activeSource, editor)
        XCTAssertEqual(session.liveLedger, original)
        XCTAssertEqual(session.ledger.categories[editor.id], .create)
        session.recordLive(seconds: 10, source: editor, day: day)
        XCTAssertEqual(session.ledger.summary(on: day).totalSeconds, 130)
    }

    func testDemoSourceSwitchAndReclassificationRemainRememberedUntilReset() {
        let day = "2026-09-15"
        var session = RatioSession()
        session.enterDemo(day: day)
        let original = session.ledger
        let first = session.availableDemoSources[0]
        let other = session.availableDemoSources[6]
        session.classify(other, as: .create)
        session.selectDemoSource(other)
        session.advanceDemo(seconds: 15, day: day)
        session.selectDemoSource(first)
        session.selectDemoSource(other)
        XCTAssertEqual(session.activeSource, other)
        XCTAssertEqual(session.ledger.categories[other.id], .create)
        XCTAssertEqual(session.ledger.summary(on: day).activities.first { $0.id == other.id }?.seconds, 855)
        session.resetDemo(day: day)
        XCTAssertEqual(session.ledger, original)
        XCTAssertNil(session.ledger.categories[other.id])
        XCTAssertEqual(session.activeSource, first)
    }

    func testDeletingActiveDemoSourceSuppressesItUntilSwitchWithoutChangingLiveActivity() throws {
        let day = "2026-09-15"
        let realSource = ActivitySource(id: "app.real", name: "Real work")
        let demoEditor = ActivitySource(id: "demo.editor", name: "Demo Editor")
        let demoBrowser = ActivitySource(id: "demo.browser", name: "demo.test", kind: .website)
        var demoLedger = ActivityLedger()
        demoLedger.record(seconds: 100, source: demoEditor, day: day)
        demoLedger.record(seconds: 50, source: demoBrowser, day: day)
        var session = RatioSession()
        session.recordLive(seconds: 60, source: realSource, day: day)
        let liveBeforeDemo = session.liveLedger
        session.enterDemo(ledger: demoLedger, activeSource: demoEditor)

        let deletion = try XCTUnwrap(session.deleteActivity(demoEditor, on: day))
        session.advanceDemo(seconds: 5, day: day)
        session.selectDemoSource(demoBrowser)
        session.advanceDemo(seconds: 3, day: day)
        session.selectDemoSource(demoEditor)
        session.advanceDemo(seconds: 2, day: day)

        XCTAssertEqual(deletion.activity.seconds, 100)
        XCTAssertEqual(session.ledger.summary(on: day).activities.first { $0.id == demoBrowser.id }?.seconds, 53)
        XCTAssertEqual(session.ledger.summary(on: day).activities.first { $0.id == demoEditor.id }?.seconds, 2)
        XCTAssertEqual(session.liveLedger, liveBeforeDemo)
    }

    func testUndoDeleteAddsOnlyRemovedTimeAndKeepsCurrentCategory() throws {
        let day = "2026-09-15"
        let editor = ActivitySource(id: "app.editor", name: "Editor")
        let browser = ActivitySource(id: "app.browser", name: "Browser")
        var session = RatioSession()
        session.classify(editor, as: .create)
        session.recordLive(seconds: 100, source: editor, day: day)
        let deletion = try XCTUnwrap(session.deleteActivity(editor, on: day))

        session.classify(editor, as: .consume)
        session.recordLive(seconds: 10, source: browser, day: day)
        session.recordLive(seconds: 3, source: editor, day: day)
        session.undoDelete(deletion)

        let restored = try XCTUnwrap(session.ledger.summary(on: day).activities.first { $0.id == editor.id })
        XCTAssertEqual(restored.seconds, 103)
        XCTAssertEqual(restored.category, .consume)
        XCTAssertEqual(session.ledger.summary(on: day).totalSeconds, 113)
    }

    func testDemoDeletionUndoCannotRestoreActivityIntoLiveDataset() throws {
        let day = "2026-09-15"
        let realSource = ActivitySource(id: "app.real", name: "Real work")
        let demoSource = ActivitySource(id: "demo.editor", name: "Demo Editor")
        var demoLedger = ActivityLedger()
        demoLedger.record(seconds: 100, source: demoSource, day: day)
        var session = RatioSession()
        session.recordLive(seconds: 60, source: realSource, day: day)
        session.enterDemo(ledger: demoLedger, activeSource: demoSource)
        let deletion = try XCTUnwrap(session.deleteActivity(demoSource, on: day))

        session.exitDemo()
        session.undoDelete(deletion)

        XCTAssertEqual(session.ledger.summary(on: day).totalSeconds, 60)
        XCTAssertEqual(session.demoLedger.summary(on: day).totalSeconds, 100)
    }
}
