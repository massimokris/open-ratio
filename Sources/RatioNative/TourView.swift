import SwiftUI

struct TourView: View {
    @EnvironmentObject private var model: AppModel
    @State private var step = 0
    var showPreferences: () -> Void = {}
    private let titles = ["Follow the active app", "Choose Create or Consume", "Read the menu bar", "Clear your unclassified queue", "Look back at your days"]
    private let explanations = [
        "Ratio follows the foreground source. Switch between fictional apps and websites below. The panel highlights the active source and adds demo time to it.",
        "Your intention decides the category. Use the panel’s ↑ Create or ↓ Consume buttons. All retained time for that source updates immediately.",
        "The menu bar shows your Create / Consume ratio and the active source’s category. Change the source or pause to see it respond.",
        "Unclassified activity counts toward tracked time, but stays out of the ratio. The panel now shows sources waiting for your choice.",
        "Each local day keeps its activity. Select a fictional day in the panel to inspect its sources. Category changes also update these past days."
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("HOW IT WORKS · \(step + 1) / 5").font(RatioTheme.font(size: 10))
                Spacer()
                Text("FICTIONAL DEMO").font(RatioTheme.font(size: 9)).foregroundStyle(RatioTheme.unknown)
            }
            Hairline()
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(titles[step]).font(RatioTheme.font(size: 23))
                    Text(explanations[step]).font(RatioTheme.font(size: 12))
                        .foregroundStyle(.secondary).lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                    interaction
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 12) {
                    MenuBarView(showPreferences: showPreferences)
                        .overlay { Rectangle().stroke(RatioTheme.line, lineWidth: 0.5) }
                    Text("Interactive demo panel · all activity here is fictional")
                        .font(RatioTheme.font(size: 9)).foregroundStyle(.secondary)
                }.frame(width: 360)
            }.frame(maxHeight: .infinity, alignment: .top)
            Text("Your real activity and pause state are preserved while you explore.")
                .font(RatioTheme.font(size: 10)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(0..<5) { index in
                    Capsule().fill(index == step ? RatioTheme.create : RatioTheme.line)
                        .frame(width: index == step ? 27 : 7, height: 4)
                }
                Spacer()
                Button("Reset Demo") { model.resetDemo(); move(to: 0) }
                    .buttonStyle(PanelButtonStyle())
                    .accessibilityHint("Restart the guide using only fictional activity")
            }
            Hairline()
            HStack {
                Button("Close Tour", action: model.closeGuidedTour)
                    .buttonStyle(PanelButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if step > 0 {
                    Button("Back") { move(to: step - 1) }.buttonStyle(QuietButtonStyle())
                }
                Button(step == 4 ? "Finish" : "Next") {
                    if step == 4 { model.closeGuidedTour() }
                    else { move(to: step + 1) }
                }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .font(RatioTheme.font(size: 11))
        .foregroundStyle(RatioTheme.text)
        .frame(width: 760, height: 600)
        .background(RatioTheme.background)
        .preferredColorScheme(model.appearance.colorScheme)
        .onAppear { model.beginGuidedTour(); move(to: 0) }
    }

    @ViewBuilder private var interaction: some View {
        switch step {
        case 0:
            sourcePicker
            Text("During real use, the foreground application changes automatically. Website capture is optional in Settings.")
                .foregroundStyle(.secondary).lineSpacing(4)
        case 1:
            sourcePicker
            Text("↑ Create     ↓ Consume")
                .foregroundStyle(RatioTheme.create)
            Text("Right-click a source row to leave it unclassified again. Your choices are personal and can change any time.")
                .foregroundStyle(.secondary).lineSpacing(4)
        case 2:
            sourcePicker
            let indicatorColor = Color(nsColor: MenuIndicator.color(category: model.activeCategory, paused: model.indicatorPaused))
            HStack(spacing: 8) {
                if model.indicatorPaused {
                    Image(nsImage: MenuIndicator.image(category: model.activeCategory, paused: true))
                        .accessibilityHidden(true)
                } else {
                    Text(MenuIndicator.glyph(category: model.activeCategory))
                        .font(Font(RatioTypography.glyphFont())).foregroundStyle(indicatorColor)
                        .accessibilityHidden(true)
                }
                Text(model.menuRatio + " D").font(RatioTheme.font()).monospacedDigit()
                    .foregroundStyle(indicatorColor)
                Spacer(minLength: 0)
                Text(model.session.isPaused ? "Paused" : (model.activeCategory?.title ?? "Unclassified"))
                    .font(RatioTheme.font(size: 10))
                    .foregroundStyle(indicatorColor)
            }.tracking(RatioTypography.letterSpacing)
                .padding(12).background(Color.black, in: RoundedRectangle(cornerRadius: 6))
                .accessibilityElement(children: .combine)
            Button(model.session.isPaused ? "Resume Demo" : "Pause Demo", action: model.togglePause)
                .buttonStyle(QuietButtonStyle())
            Text("D labels demo mode. Dashes mean no classified time.")
                .foregroundStyle(.secondary).lineSpacing(4)
        case 3:
            Text("\(model.unclassifiedCount) unclassified sources").foregroundStyle(RatioTheme.unknown)
            Button("Show Unclassified") { model.page = .today; model.filter = .unclassified }
                .buttonStyle(QuietButtonStyle())
            Text(model.unclassifiedCount == 0
                 ? "All demo sources have a category. Reset Demo to try again."
                 : "Choose ↑ or ↓ for each source in the panel. The red badge opens this queue at any time.")
                .foregroundStyle(.secondary).lineSpacing(4)
        default:
            Button("Show Daily History") { model.page = .history }.buttonStyle(QuietButtonStyle())
            Text("Use the header’s back arrow to return from a day’s sources. The footer’s list button returns to today’s tracking.")
                .foregroundStyle(.secondary).lineSpacing(4)
            Text("Export retained days from the panel or history context menu.")
                .foregroundStyle(.secondary).lineSpacing(4)
        }
    }

    private var sourcePicker: some View {
        Picker("Demo source", selection: Binding(
            get: { model.activeSource?.id ?? "" },
            set: { id in
                if let source = model.session.availableDemoSources.first(where: { $0.id == id }) {
                    model.selectDemoSource(source)
                }
            })) {
                ForEach(model.session.availableDemoSources) { source in
                    Text(source.name).tag(source.id)
                }
            }
            .pickerStyle(.menu)
            .pointingHandCursor()
    }

    private func move(to next: Int) {
        step = next
        model.page = next == 4 ? .history : .today
        model.filter = next == 3 ? .unclassified : .all
    }
}
