import XCTest
@testable import RatioCore
@testable import RatioNative

final class ActivityDeletionTests: XCTestCase {
    func testDragCommitsAtSixtyPercentExactlyOnceAndSnapsBackBelowIt() {
        var belowThreshold = ActivityDeleteGestureState()
        XCTAssertFalse(belowThreshold.update(translation: CGSize(width: 215.9, height: 0), rowWidth: 360))
        XCTAssertEqual(belowThreshold.offset, 215.9, accuracy: 0.001)
        belowThreshold.finish()
        XCTAssertEqual(belowThreshold.offset, 0)

        var atThreshold = ActivityDeleteGestureState()
        XCTAssertTrue(atThreshold.update(translation: CGSize(width: 216, height: 0), rowWidth: 360))
        XCTAssertFalse(atThreshold.update(translation: CGSize(width: 340, height: 0), rowWidth: 360))
        XCTAssertEqual(atThreshold.offset, 216)
    }

    func testCommittedDragResetsBeforeUndoRestoresTheRow() {
        var gesture = ActivityDeleteGestureState()
        XCTAssertTrue(gesture.update(translation: CGSize(width: 216, height: 0), rowWidth: 360))

        // The committed gesture must be neutral before undo can restore an
        // activity row whose SwiftUI state may have been preserved.
        gesture.finish()

        XCTAssertEqual(gesture.offset, 0)
        XCTAssertTrue(gesture.suppressesControlActivation)
        gesture.resumeControlActivation()

        XCTAssertFalse(gesture.update(translation: CGSize(width: 9, height: 10), rowWidth: 360))
        XCTAssertEqual(gesture.offset, 0)
        gesture.finish()
        gesture.resumeControlActivation()

        XCTAssertFalse(gesture.update(translation: CGSize(width: 20, height: 0), rowWidth: 360))
        XCTAssertEqual(gesture.offset, 20)
    }

    func testVerticalAndLeftwardGesturesNeverBecomeDeleteDrags() {
        var vertical = ActivityDeleteGestureState()
        XCTAssertFalse(vertical.update(translation: CGSize(width: 9, height: 10), rowWidth: 360))
        XCTAssertTrue(vertical.suppressesControlActivation)
        XCTAssertFalse(vertical.update(translation: CGSize(width: 320, height: 12), rowWidth: 360))
        XCTAssertEqual(vertical.offset, 0)

        var leftward = ActivityDeleteGestureState()
        XCTAssertFalse(leftward.update(translation: CGSize(width: -300, height: 0), rowWidth: 360))
        XCTAssertTrue(leftward.suppressesControlActivation)
        XCTAssertFalse(leftward.update(translation: CGSize(width: 320, height: 0), rowWidth: 360))
        XCTAssertEqual(leftward.offset, 0)
    }

    func testFinishingDragKeepsControlsSuppressedUntilInteractionCompletes() {
        var gesture = ActivityDeleteGestureState()
        XCTAssertFalse(gesture.update(translation: CGSize(width: 20, height: 0), rowWidth: 360))

        gesture.finish()

        XCTAssertEqual(gesture.offset, 0)
        XCTAssertTrue(gesture.suppressesControlActivation)
        gesture.resumeControlActivation()
        XCTAssertFalse(gesture.suppressesControlActivation)
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
            positions: [.all: 0],
            atUptime: 100
        )

        XCTAssertTrue(state.expire(atUptime: 105.999).isEmpty)
        XCTAssertEqual(state.pending.map(\.id), [pending.id])

        XCTAssertEqual(state.expire(atUptime: 106).map(\.id), [pending.id])
        XCTAssertTrue(state.pending.isEmpty)
    }

    func testUndoActivationRejectsPlaceholderAtDeadline() throws {
        let day = "2026-09-15"
        let source = ActivitySource(id: "app.editor", name: "Editor")
        var session = RatioSession()
        session.recordLive(seconds: 60, source: source, day: day)
        let deletion = try XCTUnwrap(session.deleteActivity(source, on: day))
        var state = ActivityDeletionState()
        let pending = state.insert(deletion, positions: [.all: 0], atUptime: 100)

        XCTAssertNil(state.take(id: pending.id, atUptime: 106))
        XCTAssertTrue(state.pending.isEmpty)
    }

    func testDelayedExpirationActivationRemovesEveryOverduePlaceholder() throws {
        let day = "2026-09-15"
        let editor = ActivitySource(id: "app.editor", name: "Editor")
        let browser = ActivitySource(id: "app.browser", name: "Browser")
        var session = RatioSession()
        session.recordLive(seconds: 60, source: editor, day: day)
        session.recordLive(seconds: 30, source: browser, day: day)
        let editorDeletion = try XCTUnwrap(session.deleteActivity(editor, on: day))
        let browserDeletion = try XCTUnwrap(session.deleteActivity(browser, on: day))
        var state = ActivityDeletionState()
        let first = state.insert(editorDeletion, positions: [.all: 0], atUptime: 100)
        let second = state.insert(browserDeletion, positions: [.all: 1], atUptime: 102)

        XCTAssertEqual(state.expire(atUptime: 109).map(\.id), [first.id, second.id])
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
            positions: [.unclassified: 0],
            atUptime: 100
        )

        let rows = state.rows(activities: [], dataset: .live, filter: .unclassified)

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
            positions: [.all: 1],
            atUptime: 100
        )

        let rows = state.rows(
            activities: session.ledger.summary(on: day).activities,
            dataset: .live,
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
            positions: [.all: 2, .unclassified: 0],
            atUptime: 100
        )

        XCTAssertEqual(
            state.rows(activities: [], dataset: .live, filter: .all).map(\.id),
            [.undo(pending.id)]
        )
        XCTAssertEqual(
            state.rows(activities: [], dataset: .live, filter: .unclassified).map(\.id),
            [.undo(pending.id)]
        )
    }

    func testActivityPositionIncludesExistingPlaceholder() throws {
        let day = "2026-09-15"
        let first = ActivitySource(id: "app.first", name: "First")
        let second = ActivitySource(id: "app.second", name: "Second")
        var session = RatioSession()
        session.recordLive(seconds: 60, source: first, day: day)
        session.recordLive(seconds: 30, source: second, day: day)
        let firstDeletion = try XCTUnwrap(session.deleteActivity(first, on: day))
        var state = ActivityDeletionState()
        state.insert(firstDeletion, positions: [.all: 0, .unclassified: 0], atUptime: 100)

        let activities = session.ledger.summary(on: day).activities
        XCTAssertEqual(
            state.position(of: second.id, activities: activities, dataset: .live, filter: .unclassified),
            1
        )
    }

    func testAllActivityPositionIncludesExistingPlaceholderAndClassifiedRow() throws {
        let day = "2026-09-15"
        let classified = ActivitySource(id: "app.classified", name: "Classified")
        let first = ActivitySource(id: "app.first", name: "First")
        let second = ActivitySource(id: "app.second", name: "Second")
        var session = RatioSession()
        session.classify(classified, as: .create)
        session.recordLive(seconds: 90, source: classified, day: day)
        session.recordLive(seconds: 60, source: first, day: day)
        session.recordLive(seconds: 30, source: second, day: day)
        let firstDeletion = try XCTUnwrap(session.deleteActivity(first, on: day))
        var state = ActivityDeletionState()
        state.insert(firstDeletion, positions: [.all: 1, .unclassified: 0], atUptime: 100)

        XCTAssertEqual(
            state.position(
                of: second.id,
                activities: session.ledger.summary(on: day).activities,
                dataset: .live,
                filter: .all
            ),
            2
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
            positions: [.all: 0],
            atUptime: 100
        )
        let browserPending = state.insert(
            browserDeletion,
            positions: [.all: 1],
            atUptime: 102
        )

        _ = state.expire(atUptime: 106)
        XCTAssertEqual(state.pending.map(\.id), [browserPending.id])
        XCTAssertNil(state.take(id: editorPending.id, atUptime: 106))
        XCTAssertEqual(state.take(id: browserPending.id, atUptime: 106)?.activityDeletion, browserDeletion)
        XCTAssertTrue(state.pending.isEmpty)
    }
}
