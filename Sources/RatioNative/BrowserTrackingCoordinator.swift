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

/// Owns local opt-ins and the native boundary; views see statuses, never a full URL.
@MainActor
final class BrowserTrackingCoordinator: ObservableObject {
    private var policy: WebsiteTrackingPolicy
    private let defaults: UserDefaults
    private let queryQueue = DispatchQueue(label: "RatioNative.browser-capture", qos: .utility)
    private var queryControl: BrowserQueryControl?
    @Published private(set) var installedBrowsers: Set<SupportedBrowser> = []
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        policy = WebsiteTrackingPolicy(enabledBrowsers: Set(SupportedBrowser.allCases.filter {
            defaults.bool(forKey: $0.preferenceKey)
        }.map(\.rawValue)))
        refreshAvailability()
    }

    var browsers: [SupportedBrowser] {
        SupportedBrowser.allCases.filter { $0 == .safari || installedBrowsers.contains($0) || isEnabled($0) }
    }
    func isEnabled(_ browser: SupportedBrowser) -> Bool { policy.enabledBrowsers.contains(browser.rawValue) }
    func status(_ browser: SupportedBrowser) -> WebsiteCaptureStatus { policy.status(for: browser.rawValue) }
    func refreshAvailability() {
        installedBrowsers = Set(SupportedBrowser.allCases.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.rawValue) != nil
        })
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    func setEnabled(_ enabled: Bool, for browser: SupportedBrowser) {
        objectWillChange.send()
        queryControl?.cancel()
        policy.setEnabled(enabled, for: browser.rawValue)
        defaults.set(enabled, forKey: browser.preferenceKey)
        onChange?()
    }

    func retry(_ browser: SupportedBrowser) {
        objectWillChange.send()
        queryControl?.cancel()
        policy.retry(browser.rawValue)
        onChange?()
    }

    func foregroundChanged(_ application: NSRunningApplication?) {
        let identity = application.flatMap { application -> BrowserIdentity? in
            guard let bundle = application.bundleIdentifier, SupportedBrowser(rawValue: bundle) != nil,
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
        let uptime = ProcessInfo.processInfo.systemUptime
        if let request = policy.beginQuery(at: uptime), let browser = SupportedBrowser(rawValue: request.browser.bundleIdentifier) {
            objectWillChange.send()
            let control = BrowserQueryControl()
            queryControl = control
            queryQueue.async { [weak self] in
                let result = BrowserAppleEvents.capture(browser, processIdentifier: request.browser.processIdentifier, control: control)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.foregroundChanged(NSWorkspace.shared.frontmostApplication)
                    self.objectWillChange.send()
                    self.policy.complete(request, with: result, at: ProcessInfo.processInfo.systemUptime)
                    if self.queryControl === control { self.queryControl = nil }
                    self.onChange?()
                }
            }
            // TCC consent can outlive an Apple event's reply timeout. Fall back promptly while
            // retaining the one native slot until that operation returns; never pile up dialogs.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self else { return }
                self.foregroundChanged(NSWorkspace.shared.frontmostApplication)
                self.objectWillChange.send()
                if self.policy.timeout(request, at: ProcessInfo.processInfo.systemUptime) {
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
        switch status(browser) {
        case .disabled: return nil
        case .tracking:
            return policy.currentHost(at: ProcessInfo.processInfo.systemUptime) == nil
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
private final class BrowserQueryControl: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
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
        guard !control.isCancelled else { return .unavailable }
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
