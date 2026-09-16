import XCTest
@testable import RatioCore
@testable import RatioNative

final class ActivityDeletionTests: XCTestCase {
    func testDragCommitsAtEightyPercentExactlyOnceAndSnapsBackBelowIt() {
        var belowThreshold = ActivityDeleteGestureState()
        XCTAssertFalse(belowThreshold.update(translation: CGSize(width: 287.9, height: 0), rowWidth: 360))
        XCTAssertEqual(belowThreshold.offset, 287.9, accuracy: 0.001)
        belowThreshold.finish()
        XCTAssertEqual(belowThreshold.offset, 0)

        var atThreshold = ActivityDeleteGestureState()
        XCTAssertTrue(atThreshold.update(translation: CGSize(width: 288, height: 0), rowWidth: 360))
        XCTAssertFalse(atThreshold.update(translation: CGSize(width: 340, height: 0), rowWidth: 360))
        XCTAssertEqual(atThreshold.offset, 288)
    }

    func testVerticalAndLeftwardGesturesNeverBecomeDeleteDrags() {
        var vertical = ActivityDeleteGestureState()
        XCTAssertFalse(vertical.update(translation: CGSize(width: 9, height: 10), rowWidth: 360))
        XCTAssertFalse(vertical.update(translation: CGSize(width: 320, height: 12), rowWidth: 360))
        XCTAssertEqual(vertical.offset, 0)

        var leftward = ActivityDeleteGestureState()
        XCTAssertFalse(leftward.update(translation: CGSize(width: -300, height: 0), rowWidth: 360))
        XCTAssertFalse(leftward.update(translation: CGSize(width: 320, height: 0), rowWidth: 360))
        XCTAssertEqual(leftward.offset, 0)
    }

    func testUndoPlaceholderExpiresAtExactlySixSeconds() throws {
        let day = "2026-09-15"
        let source = ActivitySource(id: "app.editor", name: "Editor")
        var session = RatioSession()
        session.recordLive(seconds: 60, source: source, day: day)
        let deletion = try XCTUnwrap(session.deleteActivity(source, on: day))
        var state = ActivityDeletionState()
        let pending = state.insert(
            deletion,
            isDemo: false,
            positions: [.all: 0],
            atUptime: 100
        )

        state.expire(atUptime: 105.999)
        XCTAssertEqual(state.pending.map(\.id), [pending.id])

        state.expire(atUptime: 106)
        XCTAssertTrue(state.pending.isEmpty)
    }

    func testRowsKeepSoleDeletedSourcePlaceholderAtCapturedPosition() throws {
        let day = "2026-09-15"
        let source = ActivitySource(id: "app.editor", name: "Editor")
        var session = RatioSession()
        session.recordLive(seconds: 60, source: source, day: day)
        let deletion = try XCTUnwrap(session.deleteActivity(source, on: day))
        var state = ActivityDeletionState()
        let pending = state.insert(
            deletion,
            isDemo: false,
            positions: [.unclassified: 0],
            atUptime: 100
        )

        let rows = state.rows(activities: [], isDemo: false, filter: .unclassified)

        XCTAssertEqual(rows.map(\.id), [.undo(pending.id)])
    }

    func testPlaceholderKeepsCapturedPositionAmongReorderedActivityRows() throws {
        let day = "2026-09-15"
        let editor = ActivitySource(id: "app.editor", name: "Editor")
        let browser = ActivitySource(id: "app.browser", name: "Browser")
        let chat = ActivitySource(id: "app.chat", name: "Chat")
        var session = RatioSession()
        session.recordLive(seconds: 90, source: editor, day: day)
        session.recordLive(seconds: 60, source: browser, day: day)
        session.recordLive(seconds: 30, source: chat, day: day)
        let deletion = try XCTUnwrap(session.deleteActivity(browser, on: day))
        var state = ActivityDeletionState()
        let pending = state.insert(
            deletion,
            isDemo: false,
            positions: [.all: 1],
            atUptime: 100
        )

        let rows = state.rows(
            activities: session.ledger.summary(on: day).activities,
            isDemo: false,
            filter: .all
        )

        XCTAssertEqual(rows.map(\.id), [.activity(editor.id), .undo(pending.id), .activity(chat.id)])
    }

    func testUnclassifiedPlaceholderRemainsAvailableInBothTodayFilters() throws {
        let day = "2026-09-15"
        let source = ActivitySource(id: "app.chat", name: "Chat")
        var session = RatioSession()
        session.recordLive(seconds: 30, source: source, day: day)
        let deletion = try XCTUnwrap(session.deleteActivity(source, on: day))
        var state = ActivityDeletionState()
        let pending = state.insert(
            deletion,
            isDemo: false,
            positions: [.all: 2, .unclassified: 0],
            atUptime: 100
        )

        XCTAssertEqual(
            state.rows(activities: [], isDemo: false, filter: .all).map(\.id),
            [.undo(pending.id)]
        )
        XCTAssertEqual(
            state.rows(activities: [], isDemo: false, filter: .unclassified).map(\.id),
            [.undo(pending.id)]
        )
    }

    func testUndoAndExpirationAffectOnlyTheirOwnDeletion() throws {
        let day = "2026-09-15"
        let editor = ActivitySource(id: "app.editor", name: "Editor")
        let browser = ActivitySource(id: "app.browser", name: "Browser")
        var session = RatioSession()
        session.recordLive(seconds: 60, source: editor, day: day)
        session.recordLive(seconds: 30, source: browser, day: day)
        let editorDeletion = try XCTUnwrap(session.deleteActivity(editor, on: day))
        let browserDeletion = try XCTUnwrap(session.deleteActivity(browser, on: day))
        var state = ActivityDeletionState()
        let editorPending = state.insert(
            editorDeletion,
            isDemo: false,
            positions: [.all: 0],
            atUptime: 100
        )
        let browserPending = state.insert(
            browserDeletion,
            isDemo: false,
            positions: [.all: 1],
            atUptime: 102
        )

        state.expire(atUptime: 106)
        XCTAssertEqual(state.pending.map(\.id), [browserPending.id])
        XCTAssertNil(state.take(id: editorPending.id))
        XCTAssertEqual(state.take(id: browserPending.id)?.deletion, browserDeletion)
        XCTAssertTrue(state.pending.isEmpty)
    }
}
