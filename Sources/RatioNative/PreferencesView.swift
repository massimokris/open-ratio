import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Settings").font(RatioTheme.font(size: 22))
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Appearance")
                    Picker("Appearance", selection: $model.appearance) {
                        ForEach(AppModel.Appearance.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    Text("You can also switch light and dark appearance in the panel footer.")
                        .foregroundStyle(.secondary)
                }
                Hairline()
                BrowserPreferencesView()
                Hairline()
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Local activity")
                    Text("Activity and preferences stay on this Mac.").font(RatioTheme.font(size: 13))
                    Text("Daily source totals and your remembered categories are saved in a small JSON store. Ratio Native has no account, analytics or network service. Website capture stores hostnames only, never page titles, paths or searches.")
                        .foregroundStyle(.secondary).lineSpacing(3)
                    Text("Categories apply to retained history. Unclassified time is visible but excluded from the ratio.")
                        .foregroundStyle(.secondary).lineSpacing(3)
                    Text(model.dataDirectory.path)
                        .font(RatioTheme.font(size: 10)).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Show Data Folder", action: model.revealDataDirectory).buttonStyle(QuietButtonStyle())
                    if let notice = model.storageNotice {
                        Label(notice, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(RatioTheme.unknown).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Hairline()
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "CSV export")
                    Text("Dataset: \(model.exportDatasetName)").font(RatioTheme.font(size: 12))
                    Text(model.session.isDemo
                         ? "Export contains only fictional demo days. Leave the demo to export your real activity."
                         : "Export includes all retained days, source names, categories and seconds.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Export \(model.exportDatasetName) CSV…", action: model.exportActivityCSV)
                        .buttonStyle(QuietButtonStyle())
                }
                Hairline()
                HStack {
                    Button(model.session.isDemo ? "Exit Demo" : "Try Demo") {
                        if model.session.isDemo { model.exitDemo() } else { model.startDemo() }
                    }.buttonStyle(QuietButtonStyle())
                    Button("How It Works", action: model.showTour).buttonStyle(QuietButtonStyle())
                }
                Text("Demo activity is fictional and kept separately from your real history.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Ratio Native 1.0 · macOS 13+").font(RatioTheme.font(size: 9)).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(RatioTheme.font(size: 11))
        .foregroundStyle(RatioTheme.text)
        .background(RatioTheme.background)
        .preferredColorScheme(model.appearance.colorScheme)
    }
}
