import AppKit
import CoreGraphics
import RatioCore

/// Converts native foreground, idle and session events into deterministic accounting inputs.
@MainActor
final class ForegroundActivityMonitor {
    private static let excludedBundleIdentifiers: Set<String> = [
        "com.apple.systempreferences",
        "com.apple.finder",
        "com.apple.loginwindow",
        "com.rationative.RatioNative"
    ]
    var sourceResolver: ((NSRunningApplication, ActivitySource) -> ActivitySource)?
    var onForegroundApplicationChange: ((NSRunningApplication?) -> Void)?
    var onObservation: ((ActivityObservation) -> Void)?
    var onSystemActiveChange: ((Bool) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var isAwake = true
    private var isSessionActive = true
    private let currentBundleIdentifier: String?

    init(currentBundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        self.currentBundleIdentifier = currentBundleIdentifier
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        observe(NSWorkspace.didActivateApplicationNotification, in: center) { [weak self] in
            guard let self else { return }
            self.onObservation?(self.sample())
        }
        observe(NSWorkspace.willSleepNotification, in: center) { [weak self] in self?.setAwake(false) }
        observe(NSWorkspace.didWakeNotification, in: center) { [weak self] in self?.setAwake(true) }
        observe(NSWorkspace.sessionDidResignActiveNotification, in: center) { [weak self] in self?.setSessionActive(false) }
        observe(NSWorkspace.sessionDidBecomeActiveNotification, in: center) { [weak self] in self?.setSessionActive(true) }
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any] {
            isSessionActive = session[kCGSessionOnConsoleKey as String] as? Bool ?? true
        }
        onSystemActiveChange?(isAwake && isSessionActive)
        onObservation?(sample())
    }

    func sample() -> ActivityObservation {
        // CoreGraphics' documented all-event sentinel is UInt32.max; no input-event tap is installed.
        let idle = CGEventType(rawValue: UInt32.max).map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        } ?? .infinity
        return sample(foreground: NSWorkspace.shared.frontmostApplication,
                      date: Date(), uptime: ProcessInfo.processInfo.systemUptime, idleSeconds: idle)
    }

    func sample(foreground: NSRunningApplication?, date: Date,
                uptime: TimeInterval, idleSeconds: TimeInterval) -> ActivityObservation {
        let source: ActivitySource?
        let trackableForeground = foreground.flatMap { application -> NSRunningApplication? in
            guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
            if let bundleIdentifier = application.bundleIdentifier,
               Self.excludedBundleIdentifiers.contains(bundleIdentifier) || bundleIdentifier == currentBundleIdentifier {
                return nil
            }
            return application
        }
        onForegroundApplicationChange?(trackableForeground)
        if let application = trackableForeground {
            let identity = application.bundleIdentifier ?? application.bundleURL?.path
            if let identity {
                let appSource = ActivitySource(id: "app." + identity,
                                               name: application.localizedName ?? application.bundleURL?.lastPathComponent ?? identity)
                source = sourceResolver?(application, appSource) ?? appSource
            } else { source = nil }
        } else { source = nil }
        return ActivityObservation(date: date, uptime: uptime,
                                   idleSeconds: idleSeconds, source: source)
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
    }

    private func observe(_ name: Notification.Name, in center: NotificationCenter, action: @escaping @MainActor () -> Void) {
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { action() }
        })
    }
    private func setAwake(_ awake: Bool) {
        let wasActive = isAwake && isSessionActive
        if wasActive { onObservation?(sample()) }
        isAwake = awake
        updateSystemState(wasActive: wasActive)
    }
    private func setSessionActive(_ active: Bool) {
        let wasActive = isAwake && isSessionActive
        if wasActive { onObservation?(sample()) }
        isSessionActive = active
        updateSystemState(wasActive: wasActive)
    }
    private func updateSystemState(wasActive: Bool) {
        let active = isAwake && isSessionActive
        guard active != wasActive else { return }
        onSystemActiveChange?(active)
        if active { onObservation?(sample()) }
    }
}
