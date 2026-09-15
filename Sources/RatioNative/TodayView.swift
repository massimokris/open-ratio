import SwiftUI
import RatioCore

/// The panel reserves five row heights, regardless of how many sources exist.
struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                if model.activityRows.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.filter == .unclassified ? "ALL CLASSIFIED" : "NO ACTIVITY YET")
                        Text(model.filter == .unclassified ? "Every source has a category." : "Your activity will appear here.")
                            .font(RatioTheme.font(size: 11))
                    }
                    .foregroundStyle(RatioTheme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                } else {
                    ForEach(model.activityRows) { activity in
                        ActivityRow(activity: activity,
                                    isActive: activity.id == model.activeSource?.id && !model.indicatorPaused) {
                            model.classify(activity.source, as: $0)
                        }
                    }
                }
            }
        }
        .frame(width: 360, height: 220)
    }
}

struct RatioSummaryView: View {
    let summary: DaySummary
    var body: some View {
        HStack(spacing: 0) {
            ratioLabel(summary.createPercentage, arrow: "↑", title: "CREATING", color: RatioTheme.create)
            ratioLabel(summary.createPercentage.map { 100 - $0 }, arrow: "↓", title: "CONSUMING", color: RatioTheme.consume)
        }
        .frame(height: 44)
        .overlay(alignment: .bottom) {
            GeometryReader { geometry in
                if let create = summary.createPercentage {
                    HStack(spacing: 0) {
                        Rectangle().fill(RatioTheme.create).frame(width: geometry.size.width * create / 100)
                        Rectangle().fill(RatioTheme.consume)
                    }
                } else {
                    Rectangle().fill(RatioTheme.line)
                }
            }.frame(height: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.createPercentage.map {
            String(format: "%.2f percent creating, %.2f percent consuming", $0, 100 - $0)
        } ?? "No classified time. Ratio is undefined.")
    }
    private func ratioLabel(_ percentage: Double?, arrow: String, title: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Text(arrow).foregroundStyle(color)
            HStack(spacing: 7) {
                Text(percentage.map { String(format: "%.2f%%", $0) } ?? "—")
                    .foregroundStyle(color)
                Text(title).foregroundStyle(RatioTheme.text)
            }
        }
        .font(RatioTheme.font())
        .frame(width: 164, alignment: .leading)
        .padding(.leading, 16)
    }
}

struct ActivityRow: View {
    let activity: ActivityTotal
    var isActive = false
    let classify: (ActivityCategory?) -> Void
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(activity.source.name)
                    .font(RatioTheme.font(weight: isActive ? .bold : .regular))
                    .foregroundStyle(activity.category == nil ? RatioTheme.unknown : RatioTheme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 2)
                if isActive {
                    Circle().fill(RatioTheme.category(activity.category)).frame(width: 4, height: 4)
                        .accessibilityLabel("Active source")
                }
                Text(PanelFormatting.elapsed(activity.seconds))
            }
            .padding(.leading, 16)
            .padding(.trailing, 9)
            .frame(width: 272, height: 44)
            categoryButton(.create)
            categoryButton(.consume)
        }
        .frame(height: 44)
        .background(isActive ? RatioTheme.panel : RatioTheme.background)
        .overlay(alignment: .bottom) { Hairline() }
        .contextMenu {
            Button("Leave unclassified") { classify(nil) }
        }
        .accessibilityElement(children: .contain)
    }
    private func categoryButton(_ category: ActivityCategory) -> some View {
        Button { classify(category) } label: {
            Text(category == .create ? "↑" : "↓")
                .font(RatioTheme.font(size: 12, weight: .regular))
                .foregroundStyle(activity.category == nil || activity.category == category
                                 ? RatioTheme.category(category) : RatioTheme.muted)
                .frame(width: 44, height: 44)
                .background(activity.category == category ? RatioTheme.selected : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(PanelButtonStyle())
        .overlay(alignment: .leading) { Rectangle().fill(RatioTheme.line).frame(width: 0.5) }
        .help("Classify \(activity.source.name) as \(category.title)")
        .accessibilityLabel("\(activity.source.name): \(category.title)")
        .accessibilityValue(activity.category == category ? "Selected" : "Not selected")
    }
}

/// Presentation only: totals remain numeric in the accounting domain.
enum PanelFormatting {
    static func elapsed(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.isFinite ? max(0, min(seconds, Double(Int.max / 2))) : 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
