import SwiftUI

struct BrowserPreferencesView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Website activity")
            Text("Application tracking is the default.").font(.system(size: 13, design: .monospaced))
            Text("Optional website tracking will ask for Automation access per browser. Only the hostname is used; page titles, paths and searches are never recorded.")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineSpacing(5)
        }
    }
}
