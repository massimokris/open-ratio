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
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Website activity")
            Toggle("Track websites", isOn: Binding(
                get: { coordinator.isWebsiteTrackingEnabled },
                set: { coordinator.setWebsiteTrackingEnabled($0) }
            ))
            .toggleStyle(.switch)
            .pointingHandCursor()
            Text("Default browser: \(coordinator.defaultBrowser?.name ?? "Not detected")")
                .font(RatioTheme.font(size: 13))
            Text("Only your default browser tracks individual websites. Other browsers are tracked as apps. This follows changes to your default browser in macOS.")
                .foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            Text(statusText)
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if coordinator.isWebsiteTrackingEnabled && needsRetry {
                Button("Retry access", action: coordinator.retryAccess)
                    .buttonStyle(QuietButtonStyle())
            }
            Text("macOS may ask for Automation access when you use your default browser. Only HTTP(S) hostnames are saved; page titles, paths and searches are never recorded. If access is unavailable, time stays with the browser app.")
                .foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            Button("Open Automation Settings", action: coordinator.openAutomationSettings)
                .buttonStyle(QuietButtonStyle())
            Text("Website tracking supports Safari, Google Chrome, Microsoft Edge, Brave and Chromium as your default browser. Your choice stays on this Mac.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .font(RatioTheme.font(size: 11))
        .onAppear { coordinator.refreshDefaultBrowser() }
    }

    private var statusText: String {
        guard let browser = coordinator.defaultBrowser else {
            return "Default browser not detected · application tracking continues"
        }
        guard coordinator.supportedDefaultBrowser != nil else {
            return "Website tracking is unavailable for \(browser.name) · application tracking continues"
        }
        switch coordinator.status ?? .disabled {
        case .disabled: return "Off · application tracking only"
        case .waiting: return "Enabled · bring \(browser.name) to the front to check access"
        case .checking: return "Checking website access · application tracking continues"
        case .tracking: return "Website access available · hostnames only"
        case .denied: return "Access denied · allow \(browser.name) in Automation Settings, then retry"
        case .timedOut: return "Timed out or awaiting permission · application tracking continues"
        case .unavailable: return "Website access unavailable · open a browser window, then retry"
        case .unsupportedURL: return "This tab has no supported HTTP(S) host · application tracking continues"
        }
    }

    private var needsRetry: Bool {
        coordinator.status == .denied || coordinator.status == .timedOut || coordinator.status == .unavailable
    }
}
