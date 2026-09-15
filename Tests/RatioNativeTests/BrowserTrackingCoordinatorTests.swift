import AppKit
import XCTest
import RatioCore
@testable import RatioNative

final class BrowserTrackingCoordinatorTests: XCTestCase {
    @MainActor
    func testMigrationDoesNotEnableWebsitesFromAnotherBrowsersOptIn() async throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: "websiteTracking.com.google.Chrome.enabled")
        let coordinator = BrowserTrackingCoordinator(defaults: defaults, defaultBrowserProvider: {
            DefaultBrowser(bundleIdentifier: "com.apple.Safari", name: "Safari")
        })

        XCTAssertFalse(coordinator.isWebsiteTrackingEnabled)
        XCTAssertEqual(coordinator.supportedDefaultBrowser, .safari)
        XCTAssertEqual(coordinator.status, .disabled)

        let reopened = BrowserTrackingCoordinator(defaults: defaults, defaultBrowserProvider: {
            DefaultBrowser(bundleIdentifier: "com.google.Chrome", name: "Google Chrome")
        })
        XCTAssertFalse(reopened.isWebsiteTrackingEnabled)
    }

    @MainActor
    func testMigratedSettingFollowsDefaultChangesAndRemembersExplicitOptOut() async throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: "websiteTracking.com.apple.Safari.enabled")
        var defaultBrowser = DefaultBrowser(bundleIdentifier: "com.apple.Safari", name: "Safari")
        let coordinator = BrowserTrackingCoordinator(defaults: defaults, defaultBrowserProvider: { defaultBrowser })
        XCTAssertTrue(coordinator.isWebsiteTrackingEnabled)

        defaultBrowser = DefaultBrowser(bundleIdentifier: "com.google.Chrome", name: "Google Chrome")
        coordinator.refreshDefaultBrowser()
        XCTAssertTrue(coordinator.isWebsiteTrackingEnabled)
        XCTAssertEqual(coordinator.defaultBrowser, defaultBrowser)
        XCTAssertEqual(coordinator.status, .waiting)

        coordinator.setWebsiteTrackingEnabled(false)
        let reopened = BrowserTrackingCoordinator(defaults: defaults, defaultBrowserProvider: {
            DefaultBrowser(bundleIdentifier: "com.apple.Safari", name: "Safari")
        })
        XCTAssertFalse(reopened.isWebsiteTrackingEnabled)
        XCTAssertEqual(reopened.status, .disabled)
    }

    @MainActor
    func testDefaultSwitchClearsCachedHostCancelsCaptureAndRejectsLateWebsite() async throws {
        var defaultBrowser = DefaultBrowser(bundleIdentifier: "com.apple.Safari", name: "Safari")
        let safari = BrowserApplication(bundleIdentifier: "com.apple.Safari", processIdentifier: 10)
        let chrome = BrowserApplication(bundleIdentifier: "com.google.Chrome", processIdentifier: 20)
        var foreground: NSRunningApplication? = safari
        var uptime: TimeInterval = 1000
        let capture = BrowserCaptureStub()
        let coordinator = BrowserTrackingCoordinator(defaults: try makeDefaults(),
            defaultBrowserProvider: { defaultBrowser }, foregroundApplication: { foreground },
            uptime: { uptime }, capture: capture)
        coordinator.setWebsiteTrackingEnabled(true)

        XCTAssertEqual(coordinator.resolve(safari, fallingBackTo: safari.source), safari.source)
        capture.completeFirst(with: .host(try XCTUnwrap(WebsiteHost(urlString: "https://safari.example/private?q=secret"))))
        XCTAssertEqual(coordinator.resolve(safari, fallingBackTo: safari.source).id, "website.safari.example")
        uptime = 1002
        XCTAssertEqual(coordinator.resolve(safari, fallingBackTo: safari.source).id, "website.safari.example")
        let oldCapture = try XCTUnwrap(capture.pending.first)

        defaultBrowser = DefaultBrowser(bundleIdentifier: "com.google.Chrome", name: "Google Chrome")
        XCTAssertEqual(coordinator.resolve(safari, fallingBackTo: safari.source), safari.source)
        XCTAssertTrue(oldCapture.control.isCancelled)
        foreground = chrome
        XCTAssertEqual(coordinator.resolve(chrome, fallingBackTo: chrome.source), chrome.source)
        capture.completeFirst(with: .host(try XCTUnwrap(WebsiteHost(urlString: "https://late.safari.example"))))
        XCTAssertEqual(coordinator.resolve(chrome, fallingBackTo: chrome.source), chrome.source)
        XCTAssertEqual(capture.pending.first?.browser, .chrome)
        capture.completeFirst(with: .host(try XCTUnwrap(WebsiteHost(urlString: "https://chrome.example"))))
        XCTAssertEqual(coordinator.resolve(chrome, fallingBackTo: chrome.source).id, "website.chrome.example")
    }

    @MainActor
    func testEveryNonDefaultBrowserKeepsItsApplicationSourceWithoutWebsiteRequests() async throws {
        var foreground: NSRunningApplication?
        let capture = BrowserCaptureStub()
        let coordinator = BrowserTrackingCoordinator(defaults: try makeDefaults(), defaultBrowserProvider: {
            DefaultBrowser(bundleIdentifier: "com.apple.Safari", name: "Safari")
        }, foregroundApplication: { foreground }, uptime: { 1000 }, capture: capture)
        coordinator.setWebsiteTrackingEnabled(true)

        for bundleIdentifier in ["com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser",
                                 "org.chromium.Chromium", "org.mozilla.firefox"] {
            let application = BrowserApplication(bundleIdentifier: bundleIdentifier, processIdentifier: 30)
            foreground = application
            XCTAssertEqual(coordinator.resolve(application, fallingBackTo: application.source), application.source)
            XCTAssertNil(coordinator.fallbackNotice)
        }
        XCTAssertTrue(capture.requestedBrowsers.isEmpty, "Non-default browsers must never receive an Automation request")
    }

    @MainActor
    func testUnsupportedOrMissingDefaultUsesAppTrackingAndPreservesTheGlobalSetting() async throws {
        var defaultBrowser: DefaultBrowser? = DefaultBrowser(bundleIdentifier: "org.mozilla.firefox", name: "Firefox")
        let firefox = BrowserApplication(bundleIdentifier: "org.mozilla.firefox", processIdentifier: 40)
        let safari = BrowserApplication(bundleIdentifier: "com.apple.Safari", processIdentifier: 10)
        var foreground: NSRunningApplication? = firefox
        let capture = BrowserCaptureStub()
        let coordinator = BrowserTrackingCoordinator(defaults: try makeDefaults(),
            defaultBrowserProvider: { defaultBrowser }, foregroundApplication: { foreground },
            uptime: { 1000 }, capture: capture)
        coordinator.setWebsiteTrackingEnabled(true)

        XCTAssertEqual(coordinator.defaultBrowser?.name, "Firefox")
        XCTAssertNil(coordinator.supportedDefaultBrowser)
        XCTAssertNil(coordinator.status)
        XCTAssertEqual(coordinator.resolve(firefox, fallingBackTo: firefox.source), firefox.source)

        defaultBrowser = nil
        foreground = safari
        XCTAssertEqual(coordinator.resolve(safari, fallingBackTo: safari.source), safari.source)
        XCTAssertNil(coordinator.defaultBrowser)
        XCTAssertNil(coordinator.status)
        XCTAssertTrue(coordinator.isWebsiteTrackingEnabled)
        XCTAssertTrue(capture.requestedBrowsers.isEmpty)

        defaultBrowser = DefaultBrowser(bundleIdentifier: "com.apple.Safari", name: "Safari")
        XCTAssertEqual(coordinator.resolve(safari, fallingBackTo: safari.source), safari.source)
        XCTAssertEqual(coordinator.status, .checking)
        XCTAssertEqual(capture.requestedBrowsers, [.safari])
    }

    @MainActor
    func testOptOutImmediatelyRestoresAppTrackingAndRejectsPendingHost() async throws {
        let safari = BrowserApplication(bundleIdentifier: "com.apple.Safari", processIdentifier: 10)
        var uptime: TimeInterval = 1000
        let capture = BrowserCaptureStub()
        let coordinator = BrowserTrackingCoordinator(defaults: try makeDefaults(), defaultBrowserProvider: {
            DefaultBrowser(bundleIdentifier: "com.apple.Safari", name: "Safari")
        }, foregroundApplication: { safari }, uptime: { uptime }, capture: capture)

        XCTAssertEqual(coordinator.resolve(safari, fallingBackTo: safari.source), safari.source)
        XCTAssertTrue(capture.requestedBrowsers.isEmpty)
        coordinator.setWebsiteTrackingEnabled(true)
        _ = coordinator.resolve(safari, fallingBackTo: safari.source)
        capture.completeFirst(with: .host(try XCTUnwrap(WebsiteHost(urlString: "https://example.com/private"))))
        XCTAssertEqual(coordinator.resolve(safari, fallingBackTo: safari.source).id, "website.example.com")
        uptime = 1002
        _ = coordinator.resolve(safari, fallingBackTo: safari.source)
        let pending = try XCTUnwrap(capture.pending.first)

        coordinator.setWebsiteTrackingEnabled(false)
        XCTAssertTrue(pending.control.isCancelled)
        XCTAssertEqual(coordinator.resolve(safari, fallingBackTo: safari.source), safari.source)
        capture.completeFirst(with: .host(try XCTUnwrap(WebsiteHost(urlString: "https://late.example"))))
        XCTAssertEqual(coordinator.status, .disabled)
        XCTAssertNil(coordinator.fallbackNotice)
        XCTAssertEqual(coordinator.resolve(safari, fallingBackTo: safari.source), safari.source)
        XCTAssertTrue(capture.pending.isEmpty)

        coordinator.setWebsiteTrackingEnabled(true)
        XCTAssertEqual(coordinator.resolve(safari, fallingBackTo: safari.source), safari.source)
        XCTAssertEqual(coordinator.status, .checking)
        XCTAssertEqual(capture.pending.count, 1)
    }

    @MainActor
    func testOptOutCannotRequestNewDefaultThroughAnImmediateStateObserver() async throws {
        var defaultBrowser = DefaultBrowser(bundleIdentifier: "com.apple.Safari", name: "Safari")
        let chrome = BrowserApplication(bundleIdentifier: "com.google.Chrome", processIdentifier: 20)
        let capture = BrowserCaptureStub()
        let coordinator = BrowserTrackingCoordinator(defaults: try makeDefaults(),
            defaultBrowserProvider: { defaultBrowser }, foregroundApplication: { chrome },
            uptime: { 1000 }, capture: capture)
        coordinator.setWebsiteTrackingEnabled(true)
        coordinator.onChange = { [weak coordinator] in
            _ = coordinator?.resolve(chrome, fallingBackTo: chrome.source)
        }

        defaultBrowser = DefaultBrowser(bundleIdentifier: "com.google.Chrome", name: "Google Chrome")
        coordinator.setWebsiteTrackingEnabled(false)

        XCTAssertTrue(capture.requestedBrowsers.isEmpty, "Turning websites off must not send an Automation request")
        XCTAssertEqual(coordinator.status, .disabled)
    }

    @MainActor
    func testDeniedDefaultKeepsAppTrackingUntilTheUserRetriesAccess() async throws {
        let safari = BrowserApplication(bundleIdentifier: "com.apple.Safari", processIdentifier: 10)
        let capture = BrowserCaptureStub()
        let coordinator = BrowserTrackingCoordinator(defaults: try makeDefaults(), defaultBrowserProvider: {
            DefaultBrowser(bundleIdentifier: "com.apple.Safari", name: "Safari")
        }, foregroundApplication: { safari }, uptime: { 1000 }, capture: capture)
        coordinator.setWebsiteTrackingEnabled(true)
        _ = coordinator.resolve(safari, fallingBackTo: safari.source)
        capture.completeFirst(with: .denied)

        XCTAssertEqual(coordinator.resolve(safari, fallingBackTo: safari.source), safari.source)
        XCTAssertEqual(coordinator.status, .denied)
        XCTAssertEqual(coordinator.fallbackNotice, "Safari app tracking · website access denied")
        XCTAssertTrue(capture.pending.isEmpty)

        coordinator.retryAccess()
        XCTAssertEqual(coordinator.resolve(safari, fallingBackTo: safari.source), safari.source)
        capture.completeFirst(with: .host(try XCTUnwrap(WebsiteHost(urlString: "https://example.com/path?secret=value"))))
        XCTAssertEqual(coordinator.status, .tracking)
        XCTAssertNil(coordinator.fallbackNotice)
        XCTAssertEqual(coordinator.resolve(safari, fallingBackTo: safari.source),
                       ActivitySource(id: "website.example.com", name: "example.com", kind: .website))
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "BrowserTrackingCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }
}

@MainActor
private final class BrowserCaptureStub: BrowserCapturing {
    struct Pending {
        let browser: SupportedBrowser
        let processIdentifier: Int32
        let control: BrowserQueryControl
        let completion: @MainActor (WebsiteCaptureResult) -> Void
    }
    var pending: [Pending] = []
    var requestedBrowsers: [SupportedBrowser] = []

    func capture(_ browser: SupportedBrowser, processIdentifier: Int32,
                 completion: @escaping @MainActor (WebsiteCaptureResult) -> Void) -> BrowserQueryControl {
        let control = BrowserQueryControl()
        pending.append(Pending(browser: browser, processIdentifier: processIdentifier,
                               control: control, completion: completion))
        requestedBrowsers.append(browser)
        return control
    }

    func completeFirst(with result: WebsiteCaptureResult) {
        guard !pending.isEmpty else { return XCTFail("No website capture is pending") }
        pending.removeFirst().completion(result)
    }
}

/// Replaces the running-process system boundary without opening or activating browsers.
private final class BrowserApplication: NSRunningApplication, @unchecked Sendable {
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
