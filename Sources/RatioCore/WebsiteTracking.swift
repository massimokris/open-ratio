import Foundation

/// A normalized HTTP(S) host. Full URLs are discarded at this boundary.
public struct WebsiteHost: Equatable, Sendable {
    public let value: String

    public init?(urlString: String) {
        guard let components = URLComponents(string: urlString),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              var host = components.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let hostCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-.[]:"))
        guard !host.isEmpty, host.unicodeScalars.allSatisfy({ hostCharacters.contains($0) }) else { return nil }
        value = host
    }

    public var source: ActivitySource { ActivitySource(id: "website." + value, name: value, kind: .website) }
}

public struct BrowserIdentity: Equatable, Sendable {
    public let bundleIdentifier: String
    public let processIdentifier: Int32
    public init(bundleIdentifier: String, processIdentifier: Int32) {
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
    }
}

public enum WebsiteCaptureResult: Equatable, Sendable {
    case host(WebsiteHost), denied, timedOut, unavailable, unsupportedURL
}

public enum WebsiteCaptureStatus: Equatable, Sendable {
    case disabled, waiting, checking, tracking, denied, timedOut, unavailable, unsupportedURL
}

/// Permission-independent browser capture behavior. Native adapters supply only normalized results.
public struct WebsiteTrackingPolicy {
    public struct Request: Equatable, Sendable {
        public let browser: BrowserIdentity
        fileprivate let generation: UInt64
        fileprivate let number: UInt64
    }
    public private(set) var enabledBrowsers: Set<String>
    public private(set) var foreground: BrowserIdentity?
    private var statuses: [String: WebsiteCaptureStatus] = [:]
    private var request: Request?
    private var generation: UInt64 = 0
    private var queryNumber: UInt64 = 0
    private var host: WebsiteHost?
    private var hostUptime: TimeInterval = 0
    private var nextQueryUptime: TimeInterval = 0

    public init(enabledBrowsers: Set<String> = []) { self.enabledBrowsers = enabledBrowsers }

    public func status(for bundleIdentifier: String) -> WebsiteCaptureStatus {
        guard enabledBrowsers.contains(bundleIdentifier) else { return .disabled }
        return statuses[bundleIdentifier] ?? .waiting
    }

    public mutating func setEnabled(_ enabled: Bool, for bundleIdentifier: String) {
        guard enabled != enabledBrowsers.contains(bundleIdentifier) else { return }
        if enabled { enabledBrowsers.insert(bundleIdentifier) }
        else { enabledBrowsers.remove(bundleIdentifier) }
        statuses[bundleIdentifier] = nil
        invalidate()
    }

    public mutating func setForeground(_ browser: BrowserIdentity?) {
        guard browser != foreground else { return }
        foreground = browser
        invalidate()
    }

    public mutating func retry(_ bundleIdentifier: String) {
        guard enabledBrowsers.contains(bundleIdentifier) else { return }
        statuses[bundleIdentifier] = nil
        invalidate()
    }

    private mutating func invalidate() {
        generation &+= 1
        host = nil
        nextQueryUptime = 0
        for (browser, status) in statuses where status == .checking { statuses[browser] = .waiting }
        // Keep the in-flight request occupied until its native operation finishes.
    }

    public mutating func beginQuery(at uptime: TimeInterval) -> Request? {
        guard uptime.isFinite, uptime >= nextQueryUptime, request == nil,
              let foreground, enabledBrowsers.contains(foreground.bundleIdentifier),
              status(for: foreground.bundleIdentifier) != .denied else { return nil }
        queryNumber &+= 1
        let next = Request(browser: foreground, generation: generation, number: queryNumber)
        request = next
        if host == nil { statuses[foreground.bundleIdentifier] = .checking }
        return next
    }

    @discardableResult
    public mutating func complete(_ completed: Request, with result: WebsiteCaptureResult, at uptime: TimeInterval) -> Bool {
        guard request == completed else { return false }
        request = nil
        guard completed.generation == generation, completed.browser == foreground,
              enabledBrowsers.contains(completed.browser.bundleIdentifier) else { return false }
        hostUptime = uptime
        nextQueryUptime = uptime + 1
        switch result {
        case let .host(value): host = value; statuses[completed.browser.bundleIdentifier] = .tracking
        case .denied: host = nil; statuses[completed.browser.bundleIdentifier] = .denied
        case .timedOut: host = nil; statuses[completed.browser.bundleIdentifier] = .timedOut; nextQueryUptime = uptime + 10
        case .unavailable: host = nil; statuses[completed.browser.bundleIdentifier] = .unavailable; nextQueryUptime = uptime + 10
        case .unsupportedURL: host = nil; statuses[completed.browser.bundleIdentifier] = .unsupportedURL
        }
        return true
    }

    /// A UI deadline never frees the native slot: a pending OS permission dialog may still be alive.
    @discardableResult
    public mutating func timeout(_ pending: Request, at uptime: TimeInterval) -> Bool {
        guard request == pending, pending.generation == generation else { return false }
        invalidate()
        statuses[pending.browser.bundleIdentifier] = .timedOut
        nextQueryUptime = uptime + 10
        return true
    }

    public func source(fallingBackTo application: ActivitySource, at uptime: TimeInterval) -> ActivitySource {
        currentHost(at: uptime)?.source ?? application
    }

    public func currentHost(at uptime: TimeInterval) -> WebsiteHost? {
        guard uptime.isFinite, uptime >= hostUptime, uptime - hostUptime <= 3 else { return nil }
        return host
    }
}
