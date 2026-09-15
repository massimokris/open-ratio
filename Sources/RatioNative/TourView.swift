import SwiftUI

struct TourView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    private let titles = ["A little more intention.", "Create or consume?", "One browser, many purposes.", "See your day clearly.", "Your balance, at a glance."]
    private let explanations = [
        "Ratio helps you notice the balance between making things and taking things in. This demo uses fictional activity. Your real day is kept separately.",
        "Open a source’s category menu to choose Create or Consume. Every choice is personal, and remembered. Change it any time: your ratio updates immediately.",
        "Websites can have their own categories. A video tutorial and a streaming site need not mean the same thing. Website capture is optional, and stores hostnames only.",
        "Tracked time includes unclassified activity. Your ratio uses only Create and Consume. Use the Unclassified filter to find sources waiting for a choice.",
        "The menu bar keeps your ratio close. Pause whenever you like. Explore the demo, switch the active source, and reset it as often as you wish."
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack { RatioMark(); Spacer(); Text("HOW IT WORKS · \(step + 1) / 5").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary) }
            Hairline()
            Text(titles[step]).font(.system(size: 24, design: .monospaced)).tracking(-1)
            Text(explanations[step]).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(0..<5) { index in Capsule().fill(index == step ? RatioTheme.create : RatioTheme.line).frame(width: index == step ? 27 : 7, height: 4) }
                Spacer()
            }
            HStack {
                Button("Exit tour") { dismiss() }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                if step > 0 { Button("Back") { step -= 1 }.buttonStyle(QuietButtonStyle()) }
                Button(step == 4 ? "Explore demo" : "Next") {
                    if step == 4 { dismiss() } else { step += 1 }
                }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.defaultAction)
            }.font(.system(size: 11, design: .monospaced))
        }.padding(30).frame(width: 510).background(RatioTheme.background)
    }
}
