import SwiftUI
import RatioCore

/// Fits entirely inside the primary panel's five-row activity area.
struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selectedDay: String?
    @State private var hoveredDayIdentifier: String?

    var body: some View {
        Group {
            if let selectedDay {
                dayDetail(model.session.ledger.summary(on: selectedDay))
            } else {
                historyOverview
            }
        }
        .font(RatioTheme.font())
        .frame(width: 360, height: 220)
        .background(RatioTheme.background)
        .onChange(of: selectedDay) { _ in hoveredDayIdentifier = nil }
        .onChange(of: model.today) { _ in hoveredDayIdentifier = nil }
        .onDisappear { hoveredDayIdentifier = nil }
        .contextMenu {
            Button("Export \(model.exportDatasetName) CSV…", action: model.exportActivityCSV)
        }
    }

    private var historyOverview: some View {
        let grid = DailyRatioGrid(ledger: model.session.ledger, today: model.today)
        return VStack(spacing: 0) {
            DailyRatioCalendarView(grid: grid, hoveredDayIdentifier: $hoveredDayIdentifier)
                .frame(width: 360, height: DailyRatioGridMetrics.sectionHeight)
            if model.session.ledger.history.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text("NO RECORDED DAYS").foregroundStyle(RatioTheme.text)
                    Text("Your daily balance will appear here as you use your Mac.")
                        .foregroundStyle(RatioTheme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
        .frame(width: 360, height: 220)
        .overlay {
            if let hovered = hoveredDay(in: grid) {
                DailyRatioTooltipLayout(cellFrame: hovered.frame) {
                    DailyRatioTooltip(text: hovered.day.tooltip)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func hoveredDay(in grid: DailyRatioGrid) -> (day: DailyRatioDay, frame: CGRect)? {
        guard let hoveredDayIdentifier else { return nil }
        for (column, week) in grid.weeks.enumerated() {
            guard let row = week.slots.firstIndex(where: { $0.dayIdentifier == hoveredDayIdentifier }),
                  let day = week.slots[row].day else { continue }
            return (day, DailyRatioGridMetrics.cellFrame(column: column, row: row, containerWidth: 360))
        }
        return nil
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

private struct DailyRatioCalendarView: View {
    let grid: DailyRatioGrid
    @Binding var hoveredDayIdentifier: String?

    var body: some View {
        HStack(spacing: DailyRatioGridMetrics.spacing) {
            ForEach(grid.weeks) { week in
                VStack(spacing: DailyRatioGridMetrics.spacing) {
                    ForEach(week.slots) { slot in
                        if let day = slot.day {
                            DailyRatioSquare(day: day)
                                .onHover { isHovered in
                                    if isHovered {
                                        hoveredDayIdentifier = day.dayIdentifier
                                    } else if hoveredDayIdentifier == day.dayIdentifier {
                                        hoveredDayIdentifier = nil
                                    }
                                }
                        } else {
                            Color.clear
                                .frame(
                                    width: DailyRatioGridMetrics.cellSize,
                                    height: DailyRatioGridMetrics.cellSize
                                )
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .frame(width: DailyRatioGridMetrics.width, height: DailyRatioGridMetrics.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Daily Create and Consume ratios")
    }
}

private struct DailyRatioSquare: View {
    let day: DailyRatioDay

    var body: some View {
        Group {
            switch day.presentation {
            case .noRatio:
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(RatioTheme.panel)
            case .tie:
                HStack(spacing: 0) {
                    Rectangle().fill(RatioTheme.create.opacity(day.opacity))
                    Rectangle().fill(RatioTheme.consume.opacity(day.opacity))
                }
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            case let .dominant(category, _):
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(RatioTheme.category(category).opacity(day.opacity))
            }
        }
        .frame(width: DailyRatioGridMetrics.cellSize, height: DailyRatioGridMetrics.cellSize)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.tooltip)
    }
}

private struct DailyRatioTooltip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(RatioTheme.font())
            .foregroundStyle(RatioTheme.text)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RatioTheme.panel, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(RatioTheme.line, lineWidth: 0.5)
            }
    }
}

private struct DailyRatioTooltipLayout: Layout {
    let cellFrame: CGRect

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        CGSize(width: proposal.width ?? 360, height: proposal.height ?? 220)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let tooltip = subviews.first else { return }
        let tooltipSize = tooltip.sizeThatFits(.unspecified)
        let localCenter = DailyRatioTooltipPlacement.center(
            for: cellFrame,
            tooltipSize: tooltipSize,
            within: CGRect(origin: .zero, size: bounds.size)
        )
        tooltip.place(
            at: CGPoint(x: bounds.minX + localCenter.x, y: bounds.minY + localCenter.y),
            anchor: .center,
            proposal: ProposedViewSize(width: tooltipSize.width, height: tooltipSize.height)
        )
    }
}

private struct HistoryDayRow: View {
    let day: DaySummary
    var showsDirection = false

    var body: some View {
        Group {
            if showsDirection {
                HStack(spacing: 0) {
                    Text(directionSymbol)
                        .font(Font(RatioTypography.glyphFont()))
                        .foregroundStyle(ratioColor)
                        .fixedSize()
                    Spacer(minLength: 0)
                    ratioBar.frame(width: 180)
                    Spacer(minLength: 0)
                    ratioLabel.fixedSize()
                }
            } else {
                HStack(spacing: 16) {
                    Text(HistoryFormatting.dateLabel(for: day.day))
                        .font(RatioTheme.font())
                        .foregroundStyle(RatioTheme.secondary)
                        .frame(width: 58, alignment: .leading)
                    ratioBar
                    ratioLabel.frame(width: 58, alignment: .trailing)
                }
            }
        }
        .font(RatioTheme.font(size: 12))
        .lineLimit(1)
        .padding(.horizontal, 16).frame(height: 44)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var ratioBar: some View {
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
    }

    private var ratioLabel: some View {
        Text(ratioText)
            .foregroundStyle(ratioColor)
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
    static func dateLabel(for recordedDay: String) -> String {
        RecordedDayFormatting.shortDateLabel(for: recordedDay)?.uppercased() ?? recordedDay
    }
}
