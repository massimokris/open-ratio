import SwiftUI
import RatioCore

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                RatioMark(size: 18)
                Text("ratio").font(.system(size: 17, weight: .medium, design: .monospaced))
                Spacer()
                if model.session.isDemo { Text("DEMO").font(.system(size: 9, design: .monospaced)).foregroundStyle(RatioTheme.unknown) }
                Text("TODAY").font(.system(size: 9, design: .monospaced)).tracking(1).foregroundStyle(.secondary)
            }
            RatioSummaryView(summary: model.summary, compact: true)
            Hairline()
            if let source = model.activeSource {
                HStack(spacing: 9) {
                    SourceIcon(source: source)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.name).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                        Text(model.session.isPaused ? "Paused" : "In focus now").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    CategoryPicker(source: source, category: model.activeCategory, classify: { model.classify(source, as: $0) }, compact: true)
                }
            } else {
                Text("Your day starts here. Classify activity to find your balance.")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text(ActivityFormatting.duration(model.summary.totalSeconds) + " tracked")
                Spacer()
                Text(ActivityFormatting.duration(model.summary.unclassifiedSeconds) + " unclassified").foregroundStyle(RatioTheme.unknown)
            }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            Hairline()
            HStack {
                Button(action: model.togglePause) {
                    Label(model.session.isPaused ? "Resume" : "Pause", systemImage: model.session.isPaused ? "play" : "pause")
                }.buttonStyle(QuietButtonStyle())
                Spacer()
                Button("Open dashboard") {
                    openWindow(id: "dashboard")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }.buttonStyle(QuietButtonStyle())
            }
            HStack {
                Button(model.session.isDemo ? "Exit demo" : "Try demo") {
                    if model.session.isDemo { model.exitDemo() } else { model.startDemo() }
                }
                Spacer()
                Button("Quit Ratio Native") { NSApplication.shared.terminate(nil) }
            }.buttonStyle(.plain).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
        }.padding(20).frame(width: 350).background(RatioTheme.background)
    }
}
