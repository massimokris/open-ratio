import AppKit
import XCTest
@testable import RatioNative
import RatioCore

final class BrowserAccessSetupTests: XCTestCase {
    @MainActor
    func testEnablingOpensDefaultBrowserAndRequestsAccessBeforeCapturingAnyTab() async throws {
        let access = BrowserAccessStub()
        let capture = SetupCaptureStub()
        let safari = SetupBrowserApplication(bundleIdentifier: "com.apple.Safari", processIdentifier: 10)
        let target = DefaultBrowser(bundleIdentifier: "com.apple.Safari", name: "Safari")
        let coordinator = BrowserTrackingCoordinator(defaults: try makeDefaults(),
            defaultBrowserProvider: { target }, foregroundApplication: { safari },
            uptime: { 1000 }, capture: capture, access: access)

        XCTAssertTrue(access.requests.isEmpty, "Initialization never opens a browser")
        coordinator.setWebsiteTrackingEnabled(true)
        XCTAssertEqual(access.requests.map(\.browser), [target])
        XCTAssertEqual(coordinator.accessSetupStatus, .opening)
        XCTAssertEqual(coordinator.resolve(safari, fallingBackTo: safari.source), safari.source)
        XCTAssertEqual(capture.requests.count, 0)

        access.requests[0].requesting()
        XCTAssertEqual(coordinator.accessSetupStatus, .requesting)
        coordinator.retryAccess()
        XCTAssertEqual(access.requests.count, 1, "Repeated actions cannot pile up browser launches or consent requests")
        access.completeFirst(with: .granted)
        XCTAssertNil(coordinator.accessSetupStatus)
        _ = coordinator.resolve(safari, fallingBackTo: safari.source)
        XCTAssertEqual(capture.requests.count, 1)
    }

    @MainActor
    func testDefaultChangeDuringLaunchDiscardsProgressWithoutOpeningTheNewDefault() async throws {
        var target = DefaultBrowser(bundleIdentifier: "com.apple.Safari", name: "Safari")
        let access = BrowserAccessStub()
        let coordinator = BrowserTrackingCoordinator(defaults: try makeDefaults(),
            defaultBrowserProvider: { target }, access: access)
        coordinator.setWebsiteTrackingEnabled(true)
        let pending = try XCTUnwrap(access.requests.first)

        target = DefaultBrowser(bundleIdentifier: "com.google.Chrome", name: "Google Chrome")
        pending.requesting()

        XCTAssertEqual(coordinator.defaultBrowser, target)
        XCTAssertTrue(pending.control.isCancelled)
        XCTAssertNil(coordinator.accessSetupStatus)
        access.completeFirst(with: .granted)
        XCTAssertTrue(access.requests.isEmpty, "A detected default change must never open a browser")
        XCTAssertEqual(coordinator.status, .waiting)
    }

    @MainActor
    func testOptOutKeepsNativeSlotOccupiedAndAnExplicitReenableWaitsForItsReturn() async throws {
        let access = BrowserAccessStub()
        let capture = SetupCaptureStub()
        let safari = SetupBrowserApplication(bundleIdentifier: "com.apple.Safari", processIdentifier: 10)
        let defaults = try makeDefaults()
        let coordinator = BrowserTrackingCoordinator(defaults: defaults, defaultBrowserProvider: {
            DefaultBrowser(bundleIdentifier: "com.apple.Safari", name: "Safari")
        }, foregroundApplication: { safari }, uptime: { 1000 }, capture: capture, access: access)
        coordinator.setWebsiteTrackingEnabled(true)
        let oldRequest = try XCTUnwrap(access.requests.first)
        oldRequest.requesting()
        coordinator.foregroundChanged(nil)
        XCTAssertFalse(oldRequest.control.isCancelled, "Consent remains valid when launch or a system dialog changes focus")
        coordinator.setWebsiteTrackingEnabled(false)
        XCTAssertTrue(oldRequest.control.isCancelled)
        XCTAssertNil(coordinator.accessSetupStatus)
        XCTAssertFalse(defaults.bool(forKey: "websiteTracking.enabled"))
        oldRequest.requesting()
        XCTAssertNil(coordinator.accessSetupStatus)

        coordinator.setWebsiteTrackingEnabled(true)
        coordinator.retryAccess()
        XCTAssertEqual(access.requests.count, 1, "Cancellation cannot free a still-running native permission call")
        XCTAssertEqual(coordinator.resolve(safari, fallingBackTo: safari.source), safari.source)
        XCTAssertTrue(capture.requests.isEmpty)
        access.completeFirst(with: .granted)
        XCTAssertEqual(access.requests.count, 1, "The fresh explicit enable runs only after the old call returns")
        XCTAssertEqual(coordinator.accessSetupStatus, .opening, "A cancelled grant cannot complete the new setup")
        access.requests[0].requesting()
        coordinator.setWebsiteTrackingEnabled(false)
        access.completeFirst(with: .granted)
        XCTAssertFalse(coordinator.isWebsiteTrackingEnabled)
        XCTAssertFalse(defaults.bool(forKey: "websiteTracking.enabled"))
        XCTAssertEqual(coordinator.status, .disabled)
        XCTAssertTrue(access.requests.isEmpty)
        XCTAssertTrue(capture.requests.isEmpty)
    }

    @MainActor
    func testRetryWaitsForPendingCaptureAndDiscardsItsLateHost() async throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: "websiteTracking.enabled")
        let access = BrowserAccessStub()
        let capture = SetupCaptureStub()
        let safari = SetupBrowserApplication(bundleIdentifier: "com.apple.Safari", processIdentifier: 10)
        let coordinator = BrowserTrackingCoordinator(defaults: defaults, defaultBrowserProvider: {
            DefaultBrowser(bundleIdentifier: "com.apple.Safari", name: "Safari")
        }, foregroundApplication: { safari }, uptime: { 1000 }, capture: capture, access: access)
        XCTAssertTrue(access.requests.isEmpty)
        _ = coordinator.resolve(safari, fallingBackTo: safari.source)
        let oldCapture = try XCTUnwrap(capture.requests.first)

        coordinator.retryAccess()
        coordinator.retryAccess()
        XCTAssertTrue(oldCapture.control.isCancelled)
        XCTAssertTrue(access.requests.isEmpty, "Permission setup and native tab capture share one slot")
        capture.completeFirst(with: .host(try XCTUnwrap(WebsiteHost(urlString: "https://late.example/private"))))
        XCTAssertEqual(access.requests.count, 1)
        XCTAssertEqual(coordinator.resolve(safari, fallingBackTo: safari.source), safari.source)
        XCTAssertTrue(capture.requests.isEmpty)
        access.completeFirst(with: .granted)
        _ = coordinator.resolve(safari, fallingBackTo: safari.source)
        XCTAssertEqual(capture.requests.count, 1)
        capture.completeFirst(with: .unsupportedURL)
        XCTAssertEqual(coordinator.status, .unsupportedURL, "Access can be granted while the browser has no supported tab")
        XCTAssertEqual(coordinator.resolve(safari, fallingBackTo: safari.source), safari.source)
    }

    @MainActor
    func testDeniedOrFailedSetupStaysVisibleUntilExplicitRetry() async throws {
        for result in [BrowserAccessResult.denied, .failed] {
            let access = BrowserAccessStub()
            let capture = SetupCaptureStub()
            let safari = SetupBrowserApplication(bundleIdentifier: "com.apple.Safari", processIdentifier: 10)
            let coordinator = BrowserTrackingCoordinator(defaults: try makeDefaults(), defaultBrowserProvider: {
                DefaultBrowser(bundleIdentifier: "com.apple.Safari", name: "Safari")
            }, foregroundApplication: { safari }, uptime: { 1000 }, capture: capture, access: access)
            coordinator.setWebsiteTrackingEnabled(true)
            access.completeFirst(with: result)
            switch result {
            case .denied:
                XCTAssertEqual(coordinator.accessSetupStatus, .denied)
                XCTAssertEqual(coordinator.status, .denied)
            case .failed:
                XCTAssertEqual(coordinator.accessSetupStatus, .failed)
                XCTAssertEqual(coordinator.status, .unavailable)
            case .granted: XCTFail("This example requires a failed setup")
            }
            XCTAssertEqual(coordinator.resolve(safari, fallingBackTo: safari.source), safari.source)
            XCTAssertTrue(capture.requests.isEmpty)
            XCTAssertTrue(access.requests.isEmpty)
            coordinator.retryAccess()
            XCTAssertEqual(access.requests.count, 1)
            access.completeFirst(with: .granted)
            XCTAssertNil(coordinator.accessSetupStatus)
            _ = coordinator.resolve(safari, fallingBackTo: safari.source)
            XCTAssertEqual(capture.requests.count, 1)
        }
    }

    @MainActor
    func testUnsupportedMissingAndDetectedDefaultsNeverOpenWithoutAnExplicitSupportedAction() async throws {
        let access = BrowserAccessStub()
        var target: DefaultBrowser? = DefaultBrowser(bundleIdentifier: "org.mozilla.firefox", name: "Firefox")
        let coordinator = BrowserTrackingCoordinator(defaults: try makeDefaults(),
            defaultBrowserProvider: { target }, access: access)
        coordinator.setWebsiteTrackingEnabled(true)
        coordinator.retryAccess()
        target = nil
        coordinator.refreshDefaultBrowser()
        coordinator.retryAccess()
        target = DefaultBrowser(bundleIdentifier: "com.apple.Safari", name: "Safari")
        coordinator.refreshDefaultBrowser()
        XCTAssertTrue(access.requests.isEmpty)
        XCTAssertTrue(coordinator.isWebsiteTrackingEnabled)
        coordinator.retryAccess()
        XCTAssertEqual(access.requests.map(\.browser), [target])
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "BrowserAccessSetupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }
}

@MainActor
private final class BrowserAccessStub: BrowserAccessRequesting {
    struct Request {
        let browser: DefaultBrowser
        let control: BrowserQueryControl
        let requesting: @MainActor () -> Void
        let completion: @MainActor (BrowserAccessResult) -> Void
    }
    var requests: [Request] = []

    func requestAccess(to browser: DefaultBrowser, requesting: @escaping @MainActor () -> Void,
                       completion: @escaping @MainActor (BrowserAccessResult) -> Void) -> BrowserQueryControl {
        let control = BrowserQueryControl()
        requests.append(Request(browser: browser, control: control, requesting: requesting, completion: completion))
        return control
    }

    func completeFirst(with result: BrowserAccessResult) {
        guard !requests.isEmpty else { return XCTFail("No browser access setup is pending") }
        requests.removeFirst().completion(result)
    }
}

@MainActor
private final class SetupCaptureStub: BrowserCapturing {
    struct Request {
        let control: BrowserQueryControl
        let completion: @MainActor (WebsiteCaptureResult) -> Void
    }
    var requests: [Request] = []
    func capture(_ browser: SupportedBrowser, processIdentifier: Int32,
                 completion: @escaping @MainActor (WebsiteCaptureResult) -> Void) -> BrowserQueryControl {
        let control = BrowserQueryControl()
        requests.append(Request(control: control, completion: completion))
        return control
    }
    func completeFirst(with result: WebsiteCaptureResult) {
        guard !requests.isEmpty else { return XCTFail("No website capture is pending") }
        requests.removeFirst().completion(result)
    }
}

private final class SetupBrowserApplication: NSRunningApplication, @unchecked Sendable {
    private let suppliedBundleIdentifier: String
    private let suppliedProcessIdentifier: pid_t
    init(bundleIdentifier: String, processIdentifier: pid_t) {
        suppliedBundleIdentifier = bundleIdentifier
        suppliedProcessIdentifier = processIdentifier
        super.init()
    }
    override var bundleIdentifier: String? { suppliedBundleIdentifier }
    override var processIdentifier: pid_t { suppliedProcessIdentifier }
    override var isTerminated: Bool { false }
    var source: ActivitySource { ActivitySource(id: "app." + suppliedBundleIdentifier, name: suppliedBundleIdentifier) }
}
