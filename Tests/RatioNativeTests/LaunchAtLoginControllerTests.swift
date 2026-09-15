import XCTest
@testable import RatioNative

final class LaunchAtLoginControllerTests: XCTestCase {
    @MainActor
    func testNeverRegisteredInstallationStartsOffWithoutChangingRegistration() {
        let service = LaunchAtLoginServiceStub(status: .notRegistered)

        let controller = LaunchAtLoginController(service: service)

        XCTAssertFalse(controller.isEnabled)
        XCTAssertFalse(controller.requiresApproval)
        XCTAssertNil(controller.notice)
        XCTAssertTrue(service.operations.isEmpty)
    }

    @MainActor
    func testExplicitEnableRegistersAndReflectsTheServiceResult() {
        let service = LaunchAtLoginServiceStub(status: .notRegistered)
        service.statusAfterRegister = .enabled
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(true)

        XCTAssertTrue(controller.isEnabled)
        XCTAssertFalse(controller.requiresApproval)
        XCTAssertNil(controller.notice)
        XCTAssertEqual(service.operations, ["register"])
    }

    @MainActor
    func testExplicitDisableUnregistersAndReflectsTheServiceResult() {
        let service = LaunchAtLoginServiceStub(status: .enabled)
        service.statusAfterUnregister = .notRegistered
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(false)

        XCTAssertFalse(controller.isEnabled)
        XCTAssertFalse(controller.requiresApproval)
        XCTAssertNil(controller.notice)
        XCTAssertEqual(service.operations, ["unregister"])
    }

    @MainActor
    func testApprovalRequiredRemainsOnAndExplainsHowToFinishEnabling() {
        let service = LaunchAtLoginServiceStub(status: .notRegistered)
        service.statusAfterRegister = .requiresApproval
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(true)

        XCTAssertTrue(controller.isEnabled)
        XCTAssertTrue(controller.requiresApproval)
        XCTAssertEqual(controller.notice,
                       "Approval required in System Settings before Open Ratio can open at login.")
        XCTAssertEqual(service.operations, ["register"])
    }

    @MainActor
    func testRefreshReflectsExternalStatusChangesWithoutWritingToTheService() {
        let service = LaunchAtLoginServiceStub(status: .requiresApproval)
        let controller = LaunchAtLoginController(service: service)
        service.status = .enabled

        controller.refresh()

        XCTAssertTrue(controller.isEnabled)
        XCTAssertFalse(controller.requiresApproval)
        XCTAssertNil(controller.notice)
        XCTAssertTrue(service.operations.isEmpty)
    }

    @MainActor
    func testFailedEnableKeepsTheActualOffStateAndExposesTheFailure() {
        let service = LaunchAtLoginServiceStub(status: .notRegistered)
        service.registerError = LaunchAtLoginTestError.operationFailed
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(true)

        XCTAssertFalse(controller.isEnabled)
        XCTAssertFalse(controller.requiresApproval)
        XCTAssertEqual(controller.notice,
                       "Open at login could not be enabled: The login item operation failed.")
        XCTAssertEqual(service.operations, ["register"])
    }

    @MainActor
    func testFailedDisableKeepsTheActualOnStateAndExposesTheFailure() {
        let service = LaunchAtLoginServiceStub(status: .enabled)
        service.unregisterError = LaunchAtLoginTestError.operationFailed
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(false)

        XCTAssertTrue(controller.isEnabled)
        XCTAssertFalse(controller.requiresApproval)
        XCTAssertEqual(controller.notice,
                       "Open at login could not be disabled: The login item operation failed.")
        XCTAssertEqual(service.operations, ["unregister"])
    }

    @MainActor
    func testApprovalGuidanceCanOpenLoginItemsSettingsDirectly() {
        let service = LaunchAtLoginServiceStub(status: .requiresApproval)
        let controller = LaunchAtLoginController(service: service)

        controller.openLoginItemsSettings()

        XCTAssertEqual(service.operations, ["open settings"])
    }
}

private enum LaunchAtLoginTestError: LocalizedError {
    case operationFailed

    var errorDescription: String? { "The login item operation failed." }
}

@MainActor
private final class LaunchAtLoginServiceStub: LaunchAtLoginServicing {
    var status: LaunchAtLoginServiceStatus
    var operations: [String] = []
    var statusAfterRegister: LaunchAtLoginServiceStatus?
    var statusAfterUnregister: LaunchAtLoginServiceStatus?
    var registerError: Error?
    var unregisterError: Error?

    init(status: LaunchAtLoginServiceStatus) {
        self.status = status
    }

    func register() throws {
        operations.append("register")
        if let registerError { throw registerError }
        if let statusAfterRegister { status = statusAfterRegister }
    }

    func unregister() throws {
        operations.append("unregister")
        if let unregisterError { throw unregisterError }
        if let statusAfterUnregister { status = statusAfterUnregister }
    }

    func openLoginItemsSettings() {
        operations.append("open settings")
    }
}
