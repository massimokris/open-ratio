import SwiftUI
import RatioCore

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Eyebrow(text: "One day at a time")
                Text("Your history.").font(.system(size: 25, design: .monospaced)).tracking(-1)
                if model.session.ledger.history.isEmpty {
                    Text("No recorded days yet. As you use your Mac, your daily balance will appear here.")
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                }
                ForEach(model.session.ledger.history) { day in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text(day.day); Spacer(); Text(ActivityFormatting.duration(day.totalSeconds)).foregroundStyle(.secondary) }
                        RatioSummaryView(summary: day, compact: true)
                    }.padding(22).background(RatioTheme.panel, in: RoundedRectangle(cornerRadius: 7))
                }
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
