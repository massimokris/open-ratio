import SwiftUI
import RatioCore

/// Fits entirely inside the primary panel's five-row activity area.
struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selectedDay: String?

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
        .font(RatioTheme.font())
        .frame(width: 360, height: 220)
        .background(RatioTheme.background)
        .contextMenu {
            Button("Export \(model.exportDatasetName) CSV…", action: model.exportActivityCSV)
        }
    }

    private func dayDetail(_ day: DaySummary) -> some View {
        VStack(spacing: 0) {
            HistoryDayRow(day: day, showsDirection: true)
            if day.activities.isEmpty {
                Text("No activity remains for this day.")
                    .foregroundStyle(RatioTheme.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(day.activities) { activity in
                            ActivityRow(activity: activity, isForeground: false, isTracking: false)
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
    var showsDirection = false

    var body: some View {
        HStack(spacing: 16) {
            Text(showsDirection ? directionSymbol : HistoryFormatting.dateLabel(for: day.day))
                .font(showsDirection ? Font(RatioTypography.glyphFont()) : RatioTheme.font())
                .foregroundStyle(showsDirection ? ratioColor : RatioTheme.secondary)
                .frame(width: 58, alignment: .leading)
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    if let createPercentage {
                        RatioTheme.create.frame(width: geometry.size.width * createPercentage / 100)
                        RatioTheme.consume.frame(width: geometry.size.width * (100 - createPercentage) / 100)
                    }
                }
                .frame(width: geometry.size.width, height: 2)
                .background(RatioTheme.line)
            }.frame(height: 2).accessibilityHidden(true)
            Text(ratioText)
                .foregroundStyle(ratioColor)
                .frame(width: 58, alignment: .trailing)
        }
        .font(RatioTheme.font(size: 12))
        .lineLimit(1)
        .padding(.horizontal, 16).frame(height: 44)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var createPercentage: Double? {
        guard let percentage = day.createPercentage, percentage.isFinite else { return nil }
        return min(100, max(0, percentage))
    }

    private var ratioText: String {
        guard let createPercentage else { return "—/—" }
        let create = Int(createPercentage.rounded())
        return "\(create)/\(100 - create)"
    }

    private var ratioColor: Color {
        guard createPercentage != nil else { return RatioTheme.secondary }
        if day.createSeconds > day.consumeSeconds { return RatioTheme.create }
        if day.consumeSeconds > day.createSeconds { return RatioTheme.consume }
        return RatioTheme.secondary
    }

    private var directionSymbol: String {
        guard createPercentage != nil else { return "—" }
        if day.createSeconds > day.consumeSeconds { return "↑" }
        if day.consumeSeconds > day.createSeconds { return "↓" }
        return "↔"
    }
}

enum HistoryFormatting {
    private static let recordedDayFormatter = formatter("yyyy-MM-dd")
    private static let dateLabelFormatter = formatter("MMM dd")

    static func dateLabel(for recordedDay: String) -> String {
        guard let date = recordedDayFormatter.date(from: recordedDay),
              recordedDayFormatter.string(from: date) == recordedDay else { return recordedDay }
        return dateLabelFormatter.string(from: date).uppercased()
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        // These are recorded calendar labels, so the current timezone must not shift them.
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }
}
