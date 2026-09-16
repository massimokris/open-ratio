import Foundation
import RatioCore

struct DailyRatioGrid {
    static let weekCount = 26
    let weeks: [DailyRatioWeek]

    init(ledger: ActivityLedger, today: String) {
        let calendar = Self.recordedDayCalendar
        guard let todayDate = Self.date(from: today, calendar: calendar),
              let currentWeekStart = calendar.date(
                byAdding: .day,
                value: -(calendar.component(.weekday, from: todayDate) - 1),
                to: todayDate
              ),
              let gridStart = calendar.date(
                byAdding: .weekOfYear,
                value: -(Self.weekCount - 1),
                to: currentWeekStart
              ) else {
            weeks = []
            return
        }

        weeks = (0..<Self.weekCount).compactMap { weekOffset in
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: gridStart) else {
                return nil
            }
            let slots = (0..<7).compactMap { weekdayOffset -> DailyRatioSlot? in
                guard let date = calendar.date(byAdding: .day, value: weekdayOffset, to: weekStart) else {
                    return nil
                }
                let dayIdentifier = ActivityFormatting.dayIdentifier(for: date, calendar: calendar)
                let day = date <= todayDate
                    ? DailyRatioDay(dayIdentifier: dayIdentifier, summary: ledger.summary(on: dayIdentifier))
                    : nil
                return DailyRatioSlot(dayIdentifier: dayIdentifier, day: day)
            }
            return DailyRatioWeek(slots: slots)
        }
    }

    private static var recordedDayCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = .gmt
        return calendar
    }

    private static func date(from dayIdentifier: String, calendar: Calendar) -> Date? {
        let components = dayIdentifier.split(separator: "-").compactMap { Int($0) }
        guard components.count == 3,
              let date = calendar.date(from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: components[0],
                month: components[1],
                day: components[2],
                hour: 12
              )),
              ActivityFormatting.dayIdentifier(for: date, calendar: calendar) == dayIdentifier else {
            return nil
        }
        return date
    }
}

struct DailyRatioWeek: Identifiable {
    let slots: [DailyRatioSlot]
    var id: String { slots.first?.dayIdentifier ?? "" }
}

struct DailyRatioSlot: Identifiable {
    let dayIdentifier: String
    let day: DailyRatioDay?
    var id: String { dayIdentifier }
}

struct DailyRatioDay: Identifiable {
    enum Presentation: Equatable {
        case noRatio
        case tie
        case dominant(category: ActivityCategory, percentage: Double)
    }

    let dayIdentifier: String
    let presentation: Presentation
    var id: String { dayIdentifier }

    init(dayIdentifier: String, summary: DaySummary) {
        self.dayIdentifier = dayIdentifier
        let createSeconds = summary.createSeconds
        let consumeSeconds = summary.consumeSeconds
        let classifiedSeconds = createSeconds + consumeSeconds
        guard classifiedSeconds > 0 else {
            presentation = .noRatio
            return
        }
        guard createSeconds != consumeSeconds else {
            presentation = .tie
            return
        }
        let category: ActivityCategory = createSeconds > consumeSeconds ? .create : .consume
        let dominantSeconds = max(createSeconds, consumeSeconds)
        presentation = .dominant(category: category, percentage: dominantSeconds / classifiedSeconds * 100)
    }

    var opacity: Double {
        guard case let .dominant(_, percentage) = presentation else { return 0.25 }
        return min(1, 0.25 + (percentage - 50) / 30 * 0.75)
    }

    var tooltip: String {
        let dateLabel = Self.tooltipDateLabel(for: dayIdentifier)
        switch presentation {
        case .noRatio:
            return "No ratio on \(dateLabel)"
        case .tie:
            return "50% Creating / 50% Consuming on \(dateLabel)"
        case let .dominant(category, percentage):
            let categoryLabel = category == .create ? "Creating" : "Consuming"
            return "\(Int(percentage.rounded()))% \(categoryLabel) on \(dateLabel)"
        }
    }

    private static func tooltipDateLabel(for dayIdentifier: String) -> String {
        let components = dayIdentifier.split(separator: "-").compactMap { Int($0) }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        guard components.count == 3,
              months.indices.contains(components[1] - 1),
              (1...31).contains(components[2]) else {
            return dayIdentifier
        }
        return String(format: "%@ %02d", months[components[1] - 1], components[2])
    }
}

enum DailyRatioGridMetrics {
    static let cellSize: CGFloat = 10
    static let spacing: CGFloat = 2
    static let rowCount = 7
    static let topInset: CGFloat = 16
    static let bottomInset: CGFloat = 16
    static var width: CGFloat {
        CGFloat(DailyRatioGrid.weekCount) * cellSize
            + CGFloat(DailyRatioGrid.weekCount - 1) * spacing
    }
    static var height: CGFloat {
        CGFloat(rowCount) * cellSize + CGFloat(rowCount - 1) * spacing
    }
    static var sectionHeight: CGFloat { topInset + height + bottomInset }

    static func cellFrame(column: Int, row: Int, containerWidth: CGFloat) -> CGRect {
        let originX = (containerWidth - width) / 2
        let stride = cellSize + spacing
        return CGRect(
            x: originX + CGFloat(column) * stride,
            y: topInset + CGFloat(row) * stride,
            width: cellSize,
            height: cellSize
        )
    }
}

enum DailyRatioTooltipPlacement {
    static func center(
        for cellFrame: CGRect,
        tooltipSize: CGSize,
        within bounds: CGRect,
        edgeInset: CGFloat = 4,
        gap: CGFloat = 4
    ) -> CGPoint {
        let halfWidth = tooltipSize.width / 2
        let halfHeight = tooltipSize.height / 2
        let minimumX = bounds.minX + edgeInset + halfWidth
        let maximumX = bounds.maxX - edgeInset - halfWidth
        let x = minimumX <= maximumX
            ? min(max(cellFrame.midX, minimumX), maximumX)
            : bounds.midX

        let minimumY = bounds.minY + edgeInset + halfHeight
        let maximumY = bounds.maxY - edgeInset - halfHeight
        let preferredAbove = cellFrame.minY - gap - halfHeight
        let preferredBelow = cellFrame.maxY + gap + halfHeight
        let preferredY = preferredAbove >= minimumY ? preferredAbove : preferredBelow
        let y = minimumY <= maximumY
            ? min(max(preferredY, minimumY), maximumY)
            : bounds.midY
        return CGPoint(x: x, y: y)
    }
}
