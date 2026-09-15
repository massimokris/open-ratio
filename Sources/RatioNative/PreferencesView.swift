import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Eyebrow(text: "Make it yours")
                Text("Preferences.").font(.system(size: 25, design: .monospaced)).tracking(-1)
                VStack(alignment: .leading, spacing: 16) {
                    Eyebrow(text: "Appearance")
                    Picker("Appearance", selection: $model.appearance) {
                        ForEach(AppModel.Appearance.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
                    Text("Follow your Mac, or choose a light or dark workspace.").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
                Hairline()
                BrowserPreferencesView()
                Hairline()
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Private by design")
                    Text("Your activity belongs to you.").font(.system(size: 14, design: .monospaced))
                    Text("Ratio Native works on this Mac. It has no account, analytics or network service. Categories are your choices. Unclassified time is visible, and excluded from your ratio.")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineSpacing(5)
                }
                Hairline()
                HStack {
                    Button("Try demo", action: model.startDemo).buttonStyle(QuietButtonStyle())
                    Button("How it works", action: model.showTour).buttonStyle(QuietButtonStyle())
                }
                Text("Ratio Native 1.0 · macOS 13+").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
