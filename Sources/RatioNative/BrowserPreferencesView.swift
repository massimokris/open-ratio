import SwiftUI
import RatioCore

struct BrowserPreferencesView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        BrowserSettingsContent(coordinator: model.browserTracking)
    }
}

private struct BrowserSettingsContent: View {
    @ObservedObject var coordinator: BrowserTrackingCoordinator

    var body: some View {
        PreferenceRow(title: "Track websites") {
            Button {
                coordinator.setWebsiteTrackingEnabled(!coordinator.isWebsiteTrackingEnabled)
            } label: {
                Text(coordinator.isWebsiteTrackingEnabled ? "On" : "Off")
                    .frame(width: 88, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PanelButtonStyle())
            .accessibilityLabel("Track websites")
            .accessibilityValue(coordinator.isWebsiteTrackingEnabled ? "On" : "Off")
        }
        .help("\(defaultBrowserText)\n\(statusText)\nTurning this on opens the supported default browser and requests Automation access. Only hostnames are saved; other browsers stay tracked as apps. Right-click for access options.")
        .contextMenu {
            Text(defaultBrowserText)
            Text(statusText)
            Divider()
            if coordinator.isWebsiteTrackingEnabled && needsRetry {
                Button(coordinator.status == .waiting && coordinator.accessSetupStatus == nil ? "Connect browser" : "Retry access",
                       action: coordinator.retryAccess)
            }
            Button("Open Automation Settings", action: coordinator.openAutomationSettings)
        }
        .onAppear { coordinator.refreshDefaultBrowser() }
    }

    private var defaultBrowserText: String {
        "Default browser: \(coordinator.defaultBrowser?.name ?? "Not detected")"
    }

    private var statusText: String {
        guard let browser = coordinator.defaultBrowser else {
            return "Default browser not detected · application tracking continues"
        }
        guard coordinator.supportedDefaultBrowser != nil else {
            return "Website tracking is unavailable for \(browser.name) · application tracking continues"
        }
        if let setup = coordinator.accessSetupStatus {
            switch setup {
            case .opening: return "Opening \(browser.name)…"
            case .requesting: return "Requesting access · respond to the macOS permission prompt"
            case .denied: return "macOS denied access · allow \(browser.name) in Automation Settings, then retry"
            case .failed: return "Could not open \(browser.name) or check access · retry to reconnect"
            }
        }
        switch coordinator.status ?? .disabled {
        case .disabled: return "Off · application tracking only"
        case .waiting: return "Website tracking enabled for \(browser.name)"
        case .checking: return "Checking website access · application tracking continues"
        case .tracking: return "Website access available · hostnames only"
        case .denied: return "Access denied · allow \(browser.name) in Automation Settings, then retry"
        case .timedOut: return "Timed out or awaiting permission · application tracking continues"
        case .unavailable: return "Website access unavailable · retry access to reconnect"
        case .unsupportedURL: return "This tab has no supported HTTP(S) host · application tracking continues"
        }
    }

    private var needsRetry: Bool {
        if let setup = coordinator.accessSetupStatus {
            return setup == .denied || setup == .failed
        }
        return coordinator.status == .waiting || coordinator.status == .denied
            || coordinator.status == .timedOut || coordinator.status == .unavailable
    }
}
