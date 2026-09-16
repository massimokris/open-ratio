import Foundation
import XCTest
import RatioCore

final class ActivityStoreTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ratio-store-tests-\(UUID().uuidString)")

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func testSavedActivityAndCategoriesSurviveANewStore() throws {
        let editor = ActivitySource(id: "app.editor", name: "Editor")
        let browser = ActivitySource(id: "app.browser", name: "Browser")
        var ledger = ActivityLedger()
        ledger.record(seconds: 3600, source: editor, day: "2026-09-14")
        ledger.record(seconds: 900, source: browser, day: "2026-09-15")
        ledger.classify(editor, as: .create)

        try ActivityStore(directory: directory).save(ledger)
        let loaded = try ActivityStore(directory: directory).load()

        XCTAssertEqual(loaded.ledger, ledger)
        XCTAssertEqual(loaded.ledger.summary(on: "2026-09-14").createSeconds, 3600)
        XCTAssertEqual(loaded.ledger.summary(on: "2026-09-15").unclassifiedSeconds, 900)
        XCTAssertNil(loaded.notice)
    }

    func testDeletedActivityAndItsUndoPersistAcrossNewStores() throws {
        let earlierDay = "2026-09-14"
        let today = "2026-09-15"
        let editor = ActivitySource(id: "app.editor", name: "Editor")
        var session = RatioSession()
        session.classify(editor, as: .create)
        session.recordLive(seconds: 30, source: editor, day: earlierDay)
        session.recordLive(seconds: 90, source: editor, day: today)
        let deletion = try XCTUnwrap(session.deleteActivity(editor, on: today))
        let store = ActivityStore(directory: directory)

        try store.save(session.liveLedger)
        let deleted = try ActivityStore(directory: directory).load().ledger
        XCTAssertEqual(deleted.summary(on: today).totalSeconds, 0)
        XCTAssertEqual(deleted.summary(on: earlierDay).totalSeconds, 30)
        XCTAssertEqual(deleted.categories[editor.id], .create)

        session.undoDelete(deletion)
        try store.save(session.liveLedger)
        let restored = try ActivityStore(directory: directory).load().ledger
        XCTAssertEqual(restored.summary(on: today).totalSeconds, 90)
        XCTAssertEqual(restored.categories[editor.id], .create)
    }

    func testFirstLaunchStartsWithEmptyActivity() throws {
        let loaded = try ActivityStore(directory: directory).load()

        XCTAssertEqual(loaded.ledger, ActivityLedger())
        XCTAssertNil(loaded.notice)
    }

    func testCorruptCurrentFileRecoversLastValidSaveAndRetainsOriginalBytes() throws {
        let store = ActivityStore(directory: directory)
        let editor = ActivitySource(id: "app.editor", name: "Editor")
        var ledger = ActivityLedger()
        ledger.record(seconds: 3600, source: editor, day: "2026-09-14")
        ledger.classify(editor, as: .create)
        try store.save(ledger)
        ledger.record(seconds: 1800, source: editor, day: "2026-09-15")
        try store.save(ledger)
        let corruptBytes = Data("unreadable original activity".utf8)
        try corruptBytes.write(to: store.fileURL)

        let recovered = try ActivityStore(directory: directory).load()

        XCTAssertEqual(recovered.ledger.summary(on: "2026-09-14").createSeconds, 3600)
        XCTAssertEqual(recovered.ledger.summary(on: "2026-09-15").totalSeconds, 0)
        XCTAssertTrue(try retainedCopies(containing: corruptBytes).count == 1)
        XCTAssertTrue(recovered.notice?.contains("backup") == true)
        XCTAssertTrue(recovered.notice?.contains(directory.path) == true)
        XCTAssertEqual(try store.load().ledger, recovered.ledger)
    }

    func testCorruptionWithoutBackupStartsEmptyOnlyAfterPreservingOriginal() throws {
        let store = ActivityStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let corruptBytes = Data("{ truncated history".utf8)
        try corruptBytes.write(to: store.fileURL)

        let recovered = try store.load()

        XCTAssertEqual(recovered.ledger, ActivityLedger())
        XCTAssertEqual(try retainedCopies(containing: corruptBytes).count, 1)
        XCTAssertTrue(recovered.notice?.contains("empty") == true)
        XCTAssertTrue(recovered.notice?.contains(directory.path) == true)
        try store.save(recovered.ledger)
        XCTAssertEqual(try store.load().ledger, ActivityLedger())
        XCTAssertEqual(try retainedCopies(containing: corruptBytes).count, 1)
    }

    func testFutureSchemaIsLeftUntouchedByLoadingAndSaving() throws {
        let store = ActivityStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let futureBytes = Data(#"{"schemaVersion":999,"futureActivity":["data this app cannot understand"]}"#.utf8)
        try futureBytes.write(to: store.fileURL)

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertTrue(error.localizedDescription.contains("999"))
            XCTAssertTrue(error.localizedDescription.contains("newer"))
        }
        XCTAssertThrowsError(try store.save(ActivityLedger()))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), futureBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.backupURL.path))
    }

    func testWriteFailureReportsDataLocationWithoutReplacingExistingFile() throws {
        let unrelatedBytes = Data("retain this existing file".utf8)
        try unrelatedBytes.write(to: directory)
        let store = ActivityStore(directory: directory)

        XCTAssertThrowsError(try store.save(ActivityLedger())) { error in
            XCTAssertTrue(error.localizedDescription.contains("save activity"))
            XCTAssertTrue(error.localizedDescription.contains(self.directory.path))
        }
        XCTAssertEqual(try Data(contentsOf: directory), unrelatedBytes)
    }

    func testFailedPreservationLeavesUnreadableOriginalAndBackupUntouched() throws {
        let store = ActivityStore(directory: directory)
        try store.save(ActivityLedger())
        try store.save(ActivityLedger())
        let backupBytes = try Data(contentsOf: store.backupURL)
        let corruptBytes = Data("retain this unreadable history".utf8)
        try corruptBytes.write(to: store.fileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertTrue(error.localizedDescription.contains("preserve"))
            XCTAssertTrue(error.localizedDescription.contains(self.directory.path))
        }
        XCTAssertThrowsError(try store.save(ActivityLedger()))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), corruptBytes)
        XCTAssertEqual(try Data(contentsOf: store.backupURL), backupBytes)
    }

    func testUnreadableDataFolderReportsAnErrorInsteadOfAppearingEmpty() throws {
        let store = ActivityStore(directory: directory)
        try store.save(ActivityLedger())
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertTrue(error.localizedDescription.contains("read activity"))
            XCTAssertTrue(error.localizedDescription.contains(self.directory.path))
        }
    }

    func testMissingCurrentFileRecoversRetainedBackup() throws {
        let store = ActivityStore(directory: directory)
        var ledger = ActivityLedger()
        ledger.record(seconds: 1200, source: ActivitySource(id: "app.editor", name: "Editor"), day: "2026-09-14")
        try store.save(ledger)
        try store.save(ledger)
        try FileManager.default.removeItem(at: store.fileURL)

        let recovered = try store.load()

        XCTAssertEqual(recovered.ledger.summary(on: "2026-09-14").totalSeconds, 1200)
        XCTAssertTrue(recovered.notice?.contains("backup") == true)
        XCTAssertEqual(try store.load().ledger, recovered.ledger)
    }

    func testUnreadableBackupReportsRecoveryLocationAndRetainsBothFiles() throws {
        let store = ActivityStore(directory: directory)
        try store.save(ActivityLedger())
        try store.save(ActivityLedger())
        let currentBytes = Data("unreadable current activity".utf8)
        let backupBytes = Data("unreadable backup activity".utf8)
        try currentBytes.write(to: store.fileURL)
        try backupBytes.write(to: store.backupURL)

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertTrue(error.localizedDescription.contains("backup"))
            XCTAssertTrue(error.localizedDescription.contains("retained"))
            XCTAssertTrue(error.localizedDescription.contains(self.directory.path))
        }
        XCTAssertEqual(try Data(contentsOf: store.fileURL), currentBytes)
        XCTAssertEqual(try Data(contentsOf: store.backupURL), backupBytes)
        XCTAssertEqual(try retainedCopies(containing: currentBytes).count, 1)
    }

    func testSaveDoesNotDiscardAnUnreadableBackup() throws {
        let store = ActivityStore(directory: directory)
        try store.save(ActivityLedger())
        let currentBytes = try Data(contentsOf: store.fileURL)
        let backupBytes = Data("unreadable backup to retain".utf8)
        try backupBytes.write(to: store.backupURL)

        XCTAssertThrowsError(try store.save(ActivityLedger())) { error in
            XCTAssertTrue(error.localizedDescription.contains("backup"))
        }
        XCTAssertEqual(try Data(contentsOf: store.fileURL), currentBytes)
        XCTAssertEqual(try Data(contentsOf: store.backupURL), backupBytes)
    }

    func testInvalidNegativeDurationIsPreservedAndRecoveredFromValidBackup() throws {
        let store = ActivityStore(directory: directory)
        var ledger = ActivityLedger()
        ledger.record(seconds: 30, source: ActivitySource(id: "app.editor", name: "Editor"), day: "2026-09-15")
        try store.save(ledger)
        try store.save(ledger)
        let invalid = Data(#"{"schemaVersion":1,"ledger":{"sources":{"app.editor":{"id":"app.editor","name":"Editor","kind":"application"}},"categories":{},"days":{"2026-09-15":{"app.editor":-20}}}}"#.utf8)
        try invalid.write(to: store.fileURL)

        let recovered = try store.load()

        XCTAssertEqual(recovered.ledger.summary(on: "2026-09-15").totalSeconds, 30)
        XCTAssertEqual(try retainedCopies(containing: invalid).count, 1)
        XCTAssertNotNil(recovered.notice)
    }

    private func retainedCopies(containing bytes: Data) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains("corrupt") && (try? Data(contentsOf: $0)) == bytes }
    }
}
