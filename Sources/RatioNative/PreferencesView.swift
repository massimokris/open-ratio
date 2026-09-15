import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            PreferenceRow(title: "Appearance") {
                Button {
                    model.appearance = model.appearance == .dark ? .light : .dark
                } label: {
                    Image(systemName: model.appearance == .dark ? "sun.max" : "moon")
                        .font(.system(size: 13))
                        .frame(width: 88, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PanelButtonStyle())
                .accessibilityLabel("Appearance")
                .accessibilityValue(model.appearance.rawValue)
                .help(model.appearance == .dark ? "Switch to light appearance" : "Switch to dark appearance")
            }
            BrowserPreferencesView()
            LaunchAtLoginPreferencesView(controller: model.launchAtLogin)
            PreferenceRow(title: "Demo") {
                Button {
                    if model.session.isDemo { model.exitDemo() } else { model.startDemo() }
                    model.page = .today
                } label: {
                    Text(model.session.isDemo ? "Exit" : "Try")
                        .frame(width: 88, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PanelButtonStyle())
                .accessibilityLabel(model.session.isDemo ? "Exit demo" : "Try demo")
                .help("Demo activity is fictional and kept separately from your real history.")
            }
            Spacer(minLength: 0)
        }
        .frame(width: 360, height: 264)
    }
}

private struct LaunchAtLoginPreferencesView: View {
    @ObservedObject var controller: LaunchAtLoginController

    var body: some View {
        PreferenceRow(title: "Open at start") {
            Button {
                controller.setEnabled(!controller.isEnabled)
            } label: {
                Text(controller.isEnabled ? "On" : "Off")
                    .frame(width: 88, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PanelButtonStyle())
            .accessibilityLabel("Open at start")
            .accessibilityValue(controller.isEnabled ? "On" : "Off")
        }
        .help(helpText)
        .contextMenu {
            if let notice = controller.notice { Text(notice) }
            if controller.requiresApproval {
                Divider()
                Button("Open Login Items Settings", action: controller.openLoginItemsSettings)
            }
        }
        .onAppear { controller.refresh() }
    }

    private var helpText: String {
        if let notice = controller.notice {
            return controller.requiresApproval ? "\(notice) Right-click to open Login Items settings." : notice
        }
        return controller.isEnabled
            ? "Open Ratio will open when you log in."
            : "Open Ratio will not open automatically when you log in."
    }
}

/// Settings shares the activity panel's 272/88-point label and control columns.
struct PreferenceRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .padding(.leading, 16)
                .frame(width: 272, height: 44, alignment: .leading)
            control()
                .frame(width: 88, height: 44)
                .overlay(alignment: .leading) { Rectangle().fill(RatioTheme.line).frame(width: 0.5) }
        }
        .frame(width: 360, height: 44)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Hairline() }
    }
}
