import AppKit
import CoreServices

enum BrowserAccessSetupStatus: Equatable {
    case opening, requesting, denied, failed
}

enum BrowserAccessResult {
    case granted, denied, failed
}

@MainActor
protocol BrowserAccessRequesting {
    /// Opening and consent are explicit user actions and do not inspect a browser tab.
    func requestAccess(to browser: DefaultBrowser, requesting: @escaping @MainActor () -> Void,
                       completion: @escaping @MainActor (BrowserAccessResult) -> Void) -> BrowserQueryControl
}

@MainActor
final class NativeBrowserAccess: BrowserAccessRequesting {
    private let permissionQueue = DispatchQueue(label: "RatioNative.browser-permission", qos: .userInitiated)

    func requestAccess(to browser: DefaultBrowser, requesting: @escaping @MainActor () -> Void,
                       completion: @escaping @MainActor (BrowserAccessResult) -> Void) -> BrowserQueryControl {
        let control = BrowserQueryControl()
        guard let applicationURL = browser.applicationURL,
              systemDefaultBrowser()?.bundleIdentifier == browser.bundleIdentifier else {
            DispatchQueue.main.async { completion(.failed) }
            return control
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { application, error in
            DispatchQueue.main.async {
                guard !control.isCancelled, error == nil,
                      let application, !application.isTerminated,
                      application.bundleIdentifier == browser.bundleIdentifier,
                      systemDefaultBrowser()?.bundleIdentifier == browser.bundleIdentifier else {
                    completion(.failed)
                    return
                }
                requesting()
                let processIdentifier = application.processIdentifier
                self.permissionQueue.async {
                    let result = Self.requestPermission(to: browser, processIdentifier: processIdentifier, control: control)
                    DispatchQueue.main.async { completion(result) }
                }
            }
        }
        return control
    }

    nonisolated private static func requestPermission(to browser: DefaultBrowser, processIdentifier: Int32,
                                                       control: BrowserQueryControl) -> BrowserAccessResult {
        guard !control.isCancelled,
              systemDefaultBrowser()?.bundleIdentifier == browser.bundleIdentifier,
              let application = NSRunningApplication(processIdentifier: processIdentifier),
              !application.isTerminated, application.bundleIdentifier == browser.bundleIdentifier else { return .failed }
        let target = NSAppleEventDescriptor(processIdentifier: processIdentifier)
        guard let address = target.aeDesc else { return .failed }
        // This asks for consent without reading a tab and can wait arbitrarily for the user.
        // Keep it off the main thread and retain its slot even after logical cancellation.
        guard !control.isCancelled else { return .failed }
        let result = AEDeterminePermissionToAutomateTarget(address, AEEventClass(kAECoreSuite), AEEventID(kAEGetData), true)
        switch result {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted), OSStatus(errAEEventWouldRequireUserConsent): return .denied
        default: return .failed
        }
    }
}
