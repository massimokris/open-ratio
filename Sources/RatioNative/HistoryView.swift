import SwiftUI
import RatioCore

/// Fits entirely inside the primary panel's five-row activity area.
struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedDay: String?

    var body: some View {
        VStack(spacing: 0) {
            if let selectedDay {
                dayDetail(model.session.ledger.summary(on: selectedDay))
            } else if model.session.ledger.history.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text("NO RECORDED DAYS").foregroundStyle(RatioTheme.text)
                    Text("Your daily balance will appear here as you use your Mac.")
                        .foregroundStyle(RatioTheme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.session.ledger.history) { day in
                            Button { selectedDay = day.day } label: { HistoryDayRow(day: day) }
                                .buttonStyle(PanelButtonStyle())
                                .accessibilityLabel("\(day.day), Create \(ActivityFormatting.duration(day.createSeconds)), Consume \(ActivityFormatting.duration(day.consumeSeconds)), unclassified \(ActivityFormatting.duration(day.unclassifiedSeconds)), \(ratioDescription(day))")
                                .accessibilityHint("Show source activity")
                        }
                    }
                }
            }
        }
        .font(RatioTheme.font(size: 10))
        .frame(width: 360, height: 220)
        .background(RatioTheme.background)
        .contextMenu {
            Button("Export \(model.exportDatasetName) CSV…", action: model.exportActivityCSV)
        }
        .onChange(of: model.session.isDemo) { _ in selectedDay = nil }
    }

    private func dayDetail(_ day: DaySummary) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { selectedDay = nil } label: {
                    Label("Days", systemImage: "chevron.left")
                }
                .buttonStyle(.plain).accessibilityLabel("Back to daily history")
                Spacer()
                Text(day.day).foregroundStyle(RatioTheme.secondary)
                Text(ActivityFormatting.duration(day.totalSeconds)).foregroundStyle(RatioTheme.secondary)
            }
            .padding(.horizontal, 16).frame(height: 28)
            .overlay(alignment: .bottom) { Hairline() }
            HistoryDayRow(day: day, showsDay: false)
            if day.activities.isEmpty {
                Text("No activity remains for this day.")
                    .foregroundStyle(RatioTheme.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(day.activities) { activity in
                            HStack(spacing: 8) {
                                Image(systemName: activity.source.kind == .website ? "globe" : "app")
                                    .foregroundStyle(RatioTheme.secondary).accessibilityHidden(true)
                                Text(activity.source.name).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 4)
                                Text(ActivityFormatting.duration(activity.seconds)).monospacedDigit()
                                Text(activity.category?.title ?? "Unclassified")
                                    .foregroundStyle(RatioTheme.category(activity.category))
                            }
                            .padding(.horizontal, 16).frame(height: 36)
                            .overlay(alignment: .bottom) { Hairline() }
                            .help(activity.source.name)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }

    private func ratioDescription(_ day: DaySummary) -> String {
        day.createPercentage.map { String(format: "%.2f percent Create", $0) } ?? "No classified time"
    }
}

private struct HistoryDayRow: View {
    let day: DaySummary
    var showsDay = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(showsDay ? day.day : "Create / Consume")
                Spacer(minLength: 4)
                if let create = day.createPercentage {
                    Text(String(format: "%.2f%%", create)).foregroundStyle(RatioTheme.create)
                    Text(String(format: "%.2f%%", 100 - create)).foregroundStyle(RatioTheme.consume)
                } else {
                    Text("— / —").foregroundStyle(RatioTheme.secondary)
                    Text("No classified time").font(RatioTheme.font(size: 8)).foregroundStyle(RatioTheme.secondary)
                }
                if showsDay { Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(RatioTheme.secondary) }
            }.monospacedDigit()
            HStack(spacing: 6) {
                Text("↑ \(ActivityFormatting.duration(day.createSeconds))").foregroundStyle(RatioTheme.create)
                Text("↓ \(ActivityFormatting.duration(day.consumeSeconds))").foregroundStyle(RatioTheme.consume)
                Text("? \(ActivityFormatting.duration(day.unclassifiedSeconds))").foregroundStyle(RatioTheme.secondary)
                Spacer(minLength: 0)
                if showsDay { Text(ActivityFormatting.duration(day.totalSeconds)).foregroundStyle(RatioTheme.secondary) }
            }.font(RatioTheme.font(size: 8))
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    RatioTheme.create.frame(width: geometry.size.width * (day.createPercentage ?? 0) / 100)
                    RatioTheme.consume.frame(width: geometry.size.width * (day.createPercentage.map { 100 - $0 } ?? 0) / 100)
                }.background(RatioTheme.line)
            }.frame(height: 2).accessibilityHidden(true)
        }
        .padding(.horizontal, 16).frame(height: 44)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Hairline() }
    }
}
