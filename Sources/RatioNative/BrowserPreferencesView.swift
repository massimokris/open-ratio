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
            Text("Application tracking is the default.").font(RatioTheme.font(size: 13))
            Text("Enable a browser, then bring it to the front. macOS may ask you to allow Automation access. Only HTTP(S) hostnames are retained; page titles, paths and searches are never recorded.")
                .foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            ForEach(coordinator.browsers) { browser in
                VStack(alignment: .leading, spacing: 5) {
                    Toggle(browser.name, isOn: Binding(
                        get: { coordinator.isEnabled(browser) },
                        set: { coordinator.setEnabled($0, for: browser) }
                    ))
                    .toggleStyle(.switch)
                    .disabled(!coordinator.installedBrowsers.contains(browser) && !coordinator.isEnabled(browser))
                    .accessibilityLabel("Track websites in \(browser.name)")
                    Text(statusText(browser)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if coordinator.isEnabled(browser), needsRetry(coordinator.status(browser)) {
                        Button("Retry \(browser.name) Access") { coordinator.retry(browser) }
                            .buttonStyle(QuietButtonStyle())
                    }
                }
                .padding(.vertical, 3)
            }
            Text("If access is denied, times out, or the active tab has no HTTP(S) host, activity stays with the browser app. Each website starts unclassified, independently of its browser.")
                .foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            Button("Open Automation Settings", action: coordinator.openAutomationSettings)
                .buttonStyle(QuietButtonStyle())
            Text("Safari and installed Google Chrome, Microsoft Edge, Brave and Chromium are supported. Opt-ins stay on this Mac.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .font(RatioTheme.font(size: 11))
        .onAppear { coordinator.refreshAvailability() }
    }

    private func statusText(_ browser: SupportedBrowser) -> String {
        guard coordinator.installedBrowsers.contains(browser) else { return "Not installed · application tracking only" }
        switch coordinator.status(browser) {
        case .disabled: return "Off · application tracking only"
        case .waiting: return "Enabled · bring this browser to the front to check access"
        case .checking: return "Checking website access · application tracking continues"
        case .tracking: return "Website access available · hostnames only"
        case .denied: return "Access denied · application tracking continues. Allow this browser in Automation Settings, then retry."
        case .timedOut: return "Timed out or awaiting permission · application tracking continues"
        case .unavailable: return "Website access unavailable · application tracking continues. Open a browser window to retry."
        case .unsupportedURL: return "This tab has no supported HTTP(S) host · application tracking continues"
        }
    }

    private func needsRetry(_ status: WebsiteCaptureStatus) -> Bool {
        status == .denied || status == .timedOut || status == .unavailable
    }
}
