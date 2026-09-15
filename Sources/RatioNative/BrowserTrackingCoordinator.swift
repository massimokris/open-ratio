import AppKit
import CoreServices
import RatioCore

enum SupportedBrowser: String, CaseIterable, Identifiable {
    case safari = "com.apple.Safari"
    case chrome = "com.google.Chrome"
    case edge = "com.microsoft.edgemac"
    case brave = "com.brave.Browser"
    case chromium = "org.chromium.Chromium"

    var id: String { rawValue }
    var name: String {
        switch self {
        case .safari: return "Safari"
        case .chrome: return "Google Chrome"
        case .edge: return "Microsoft Edge"
        case .brave: return "Brave"
        case .chromium: return "Chromium"
        }
    }
    var preferenceKey: String { "websiteTracking.\(rawValue).enabled" }
}

struct DefaultBrowser: Equatable {
    let bundleIdentifier: String
    let name: String
}

private func systemDefaultBrowser() -> DefaultBrowser? {
    guard let webURL = URL(string: "https://example.com"),
          let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: webURL),
          let bundle = Bundle(url: applicationURL), let identifier = bundle.bundleIdentifier else { return nil }
    let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? applicationURL.deletingPathExtension().lastPathComponent
    return DefaultBrowser(bundleIdentifier: identifier, name: name)
}

/// Owns the local opt-in and native boundary; views see statuses, never a full URL.
@MainActor
final class BrowserTrackingCoordinator: ObservableObject {
    private static let preferenceKey = "websiteTracking.enabled"
    private var policy: WebsiteTrackingPolicy
    private let defaults: UserDefaults
    private let defaultBrowserProvider: () -> DefaultBrowser?
    private let foregroundApplication: () -> NSRunningApplication?
    private let uptime: () -> TimeInterval
    private let capture: BrowserCapturing
    private var queryControl: BrowserQueryControl?
    @Published private(set) var defaultBrowser: DefaultBrowser?
    @Published private(set) var isWebsiteTrackingEnabled: Bool
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard,
         defaultBrowserProvider: @escaping () -> DefaultBrowser? = { systemDefaultBrowser() },
         foregroundApplication: @escaping () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication },
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         capture: BrowserCapturing? = nil) {
        self.defaults = defaults
        self.defaultBrowserProvider = defaultBrowserProvider
        self.foregroundApplication = foregroundApplication
        self.uptime = uptime
        self.capture = capture ?? NativeBrowserCapture()
        let defaultBrowser = defaultBrowserProvider()
        self.defaultBrowser = defaultBrowser
        let supportedBrowser = defaultBrowser.flatMap { SupportedBrowser(rawValue: $0.bundleIdentifier) }
        let enabled = defaults.object(forKey: Self.preferenceKey) != nil
            ? defaults.bool(forKey: Self.preferenceKey)
            : supportedBrowser.map { defaults.bool(forKey: $0.preferenceKey) } ?? false
        isWebsiteTrackingEnabled = enabled
        defaults.set(enabled, forKey: Self.preferenceKey)
        policy = WebsiteTrackingPolicy(enabledBrowsers: enabled ? Set(supportedBrowser.map { [$0.rawValue] } ?? []) : [])
    }

    var supportedDefaultBrowser: SupportedBrowser? {
        defaultBrowser.flatMap { SupportedBrowser(rawValue: $0.bundleIdentifier) }
    }
    var status: WebsiteCaptureStatus? {
        supportedDefaultBrowser.map { policy.status(for: $0.rawValue) }
    }

    func refreshDefaultBrowser() {
        let detected = defaultBrowserProvider()
        guard detected != defaultBrowser else { return }
        let previousIdentifier = defaultBrowser?.bundleIdentifier
        defaultBrowser = detected
        if previousIdentifier != detected?.bundleIdentifier {
            queryControl?.cancel()
            for browser in policy.enabledBrowsers { policy.setEnabled(false, for: browser) }
            if isWebsiteTrackingEnabled, let browser = supportedDefaultBrowser {
                policy.setEnabled(true, for: browser.rawValue)
            }
            policy.setForeground(nil)
        }
        onChange?()
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    func setWebsiteTrackingEnabled(_ enabled: Bool) {
        guard enabled != isWebsiteTrackingEnabled else {
            refreshDefaultBrowser()
            return
        }
        objectWillChange.send()
        queryControl?.cancel()
        isWebsiteTrackingEnabled = enabled
        if let browser = supportedDefaultBrowser { policy.setEnabled(enabled, for: browser.rawValue) }
        defaults.set(enabled, forKey: Self.preferenceKey)
        // A default change can synchronously refresh tracking through onChange. Apply the
        // user's choice first so an opt-out cannot start a capture for the new default.
        refreshDefaultBrowser()
        onChange?()
    }

    func retryAccess() {
        refreshDefaultBrowser()
        guard let browser = supportedDefaultBrowser else { return }
        objectWillChange.send()
        queryControl?.cancel()
        policy.retry(browser.rawValue)
        onChange?()
    }

    func foregroundChanged(_ application: NSRunningApplication?) {
        refreshDefaultBrowser()
        let identity = application.flatMap { application -> BrowserIdentity? in
            guard let bundle = application.bundleIdentifier, bundle == supportedDefaultBrowser?.rawValue,
                  !application.isTerminated else { return nil }
            return BrowserIdentity(bundleIdentifier: bundle, processIdentifier: application.processIdentifier)
        }
        guard identity != policy.foreground else { return }
        objectWillChange.send()
        queryControl?.cancel()
        policy.setForeground(identity)
    }

    func resolve(_ application: NSRunningApplication, fallingBackTo source: ActivitySource) -> ActivitySource {
        foregroundChanged(application)
        let uptime = uptime()
        if let request = policy.beginQuery(at: uptime), let browser = SupportedBrowser(rawValue: request.browser.bundleIdentifier) {
            objectWillChange.send()
            let control = capture.capture(browser, processIdentifier: request.browser.processIdentifier) { [weak self] result in
                guard let self else { return }
                self.foregroundChanged(self.foregroundApplication())
                self.objectWillChange.send()
                self.policy.complete(request, with: result, at: self.uptime())
                self.queryControl = nil
                self.onChange?()
            }
            queryControl = control
            // TCC consent can outlive an Apple event's reply timeout. Fall back promptly while
            // retaining the one native slot until that operation returns; never pile up dialogs.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self else { return }
                self.foregroundChanged(self.foregroundApplication())
                self.objectWillChange.send()
                if self.policy.timeout(request, at: self.uptime()) {
                    control.cancel()
                    self.onChange?()
                }
            }
        }
        return policy.source(fallingBackTo: source, at: uptime)
    }

    var fallbackNotice: String? {
        guard let foreground = policy.foreground, policy.enabledBrowsers.contains(foreground.bundleIdentifier),
              let browser = SupportedBrowser(rawValue: foreground.bundleIdentifier) else { return nil }
        switch policy.status(for: browser.rawValue) {
        case .disabled: return nil
        case .tracking:
            return policy.currentHost(at: uptime()) == nil
                ? "\(browser.name) app tracking · refreshing website access" : nil
        case .waiting, .checking: return "\(browser.name) app tracking · checking website access"
        case .denied: return "\(browser.name) app tracking · website access denied"
        case .timedOut: return "\(browser.name) app tracking · website access timed out or awaits permission"
        case .unavailable: return "\(browser.name) app tracking · website access unavailable"
        case .unsupportedURL: return "\(browser.name) app tracking · active tab has no supported HTTP(S) host"
        }
    }
}

/// A queued capture checks cancellation before sending an event, even after opt-out or focus loss.
// The only mutable field is protected by the lock on both worker and main queues.
final class BrowserQueryControl: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

@MainActor
protocol BrowserCapturing {
    /// Completion is delivered asynchronously on the main actor, with no URL retained.
    func capture(_ browser: SupportedBrowser, processIdentifier: Int32,
                 completion: @escaping @MainActor (WebsiteCaptureResult) -> Void) -> BrowserQueryControl
}

@MainActor
private final class NativeBrowserCapture: BrowserCapturing {
    private let queryQueue = DispatchQueue(label: "RatioNative.browser-capture", qos: .utility)

    func capture(_ browser: SupportedBrowser, processIdentifier: Int32,
                 completion: @escaping @MainActor (WebsiteCaptureResult) -> Void) -> BrowserQueryControl {
        let control = BrowserQueryControl()
        queryQueue.async {
            let result = BrowserAppleEvents.capture(browser, processIdentifier: processIdentifier, control: control)
            DispatchQueue.main.async { completion(result) }
        }
        return control
    }
}

private enum BrowserAppleEvents {
    static func capture(_ browser: SupportedBrowser, processIdentifier: Int32, control: BrowserQueryControl) -> WebsiteCaptureResult {
        guard !control.isCancelled,
              let application = NSRunningApplication(processIdentifier: processIdentifier),
              application.bundleIdentifier == browser.rawValue, application.isActive, !application.isTerminated else { return .unavailable }
        // Address the existing process, not a bundle URL: this cannot launch a background browser.
        let target = NSAppleEventDescriptor(processIdentifier: processIdentifier)
        guard let window = object(desiredClass: OSType(cWindow), container: .null(),
                                  form: OSType(formAbsolutePosition), data: NSAppleEventDescriptor(int32: 1)),
              // Safari's current tab is 'cTab'; Chromium's active tab is 'acTa'.
              let tab = property(browser == .safari ? 0x63546162 : 0x61635461, of: window),
              // Safari uses 'pURL'; Chromium uses 'URL '. These are fixed dictionary codes.
              let url = property(browser == .safari ? OSType(pURL) : 0x55524C20, of: tab) else { return .unavailable }
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kAECoreSuite), eventID: AEEventID(kAEGetData),
                                           targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(url, forKeyword: AEKeyword(keyDirectObject))
        // Recheck at the native boundary: the HTTPS handler may change while work is queued.
        guard !control.isCancelled,
              systemDefaultBrowser()?.bundleIdentifier == browser.rawValue else { return .unavailable }
        do {
            let reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 2)
            let error = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber))?.int32Value ?? 0
            guard error == 0 else { return failure(error) }
            // Neither native error text nor the raw URL escapes this function. Only a host can.
            guard let rawURL = reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
                  let host = WebsiteHost(urlString: rawURL) else { return .unsupportedURL }
            return .host(host)
        } catch {
            return Int32(exactly: (error as NSError).code).map(failure) ?? .unavailable
        }
    }

    private static func failure(_ code: Int32) -> WebsiteCaptureResult {
        switch code {
        case Int32(errAEEventNotPermitted), Int32(errAEEventWouldRequireUserConsent): return .denied
        case Int32(errAETimeout): return .timedOut
        default: return .unavailable
        }
    }

    private static func property(_ code: OSType, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor? {
        object(desiredClass: OSType(cProperty), container: container, form: OSType(formPropertyID),
               data: NSAppleEventDescriptor(typeCode: code))
    }

    private static func object(desiredClass: OSType, container: NSAppleEventDescriptor,
                               form: OSType, data: NSAppleEventDescriptor) -> NSAppleEventDescriptor? {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: desiredClass), forKeyword: AEKeyword(keyAEDesiredClass))
        record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: form), forKeyword: AEKeyword(keyAEKeyForm))
        record.setDescriptor(data, forKeyword: AEKeyword(keyAEKeyData))
        return record.coerce(toDescriptorType: DescType(typeObjectSpecifier))
    }
}
