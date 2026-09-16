import Foundation
import RatioCore

/// Interprets persisted local-day labels without applying the Mac's current timezone.
enum RecordedDayFormatting {
    private static let identifierFormatter = formatter("yyyy-MM-dd")
    private static let shortDateFormatter = formatter("MMM dd")

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        // GMT makes date-only arithmetic deterministic; it does not rebucket the recorded local-day label.
        calendar.timeZone = .gmt
        return calendar
    }

    static func date(from dayIdentifier: String) -> Date? {
        guard let date = identifierFormatter.date(from: dayIdentifier),
              identifierFormatter.string(from: date) == dayIdentifier else {
            return nil
        }
        return date
    }

    static func identifier(for date: Date) -> String {
        identifierFormatter.string(from: date)
    }

    static func shortDateLabel(for dayIdentifier: String) -> String? {
        guard let date = date(from: dayIdentifier) else { return nil }
        return shortDateFormatter.string(from: date)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = .gmt
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }
}

struct DailyRatioGrid {
    static let weekCount = 26
    let weeks: [DailyRatioWeek]

    init(ledger: ActivityLedger, today: String) {
        let calendar = RecordedDayFormatting.calendar
        guard let todayDate = RecordedDayFormatting.date(from: today) else {
            weeks = []
            return
        }
        // Gregorian weekday numbering is Sunday = 1, regardless of the locale's first weekday.
        let daysSinceSunday = calendar.component(.weekday, from: todayDate) - 1
        let oldestWeekOffset = -7 * (Self.weekCount - 1)
        guard let currentWeekStart = calendar.date(byAdding: .day, value: -daysSinceSunday, to: todayDate),
              let gridStart = calendar.date(byAdding: .day, value: oldestWeekOffset, to: currentWeekStart) else {
            weeks = []
            return
        }

        weeks = (0..<Self.weekCount).compactMap { weekOffset in
            guard let weekStart = calendar.date(byAdding: .day, value: weekOffset * 7, to: gridStart) else {
                return nil
            }
            let slots = (0..<7).compactMap { weekdayOffset -> DailyRatioSlot? in
                guard let date = calendar.date(byAdding: .day, value: weekdayOffset, to: weekStart) else {
                    return nil
                }
                let dayIdentifier = RecordedDayFormatting.identifier(for: date)
                let day = date <= todayDate
                    ? DailyRatioDay(dayIdentifier: dayIdentifier, summary: ledger.summary(on: dayIdentifier))
                    : nil
                return DailyRatioSlot(dayIdentifier: dayIdentifier, day: day)
            }
            return DailyRatioWeek(slots: slots)
        }
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
        guard let createPercentage = summary.createPercentage, createPercentage.isFinite else {
            presentation = .noRatio
            return
        }
        guard createSeconds != consumeSeconds else {
            presentation = .tie
            return
        }
        let category: ActivityCategory = createSeconds > consumeSeconds ? .create : .consume
        let dominantPercentage = category == .create ? createPercentage : 100 - createPercentage
        presentation = .dominant(category: category, percentage: dominantPercentage)
    }

    var opacity: Double {
        guard case let .dominant(_, percentage) = presentation else { return 0.25 }
        return min(1, 0.25 + (percentage - 50) / 30 * 0.75)
    }

    var tooltip: String {
        let dateLabel = RecordedDayFormatting.shortDateLabel(for: dayIdentifier) ?? dayIdentifier
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
}

enum DailyRatioGridMetrics {
    static let cellSize: CGFloat = 10
    static let rowSpacing: CGFloat = 2
    static let rowCount = 7
    static let panelWidth: CGFloat = 360
    static let contentSideInset: CGFloat = 16
    static let topInset: CGFloat = 16
    static let bottomInset: CGFloat = 16
    static var width: CGFloat {
        panelWidth - contentSideInset * 2
    }
    static var columnSpacing: CGFloat {
        let cellsWidth = CGFloat(DailyRatioGrid.weekCount) * cellSize
        return (width - cellsWidth) / CGFloat(DailyRatioGrid.weekCount - 1)
    }
    static var height: CGFloat {
        CGFloat(rowCount) * cellSize + CGFloat(rowCount - 1) * rowSpacing
    }
    static var sectionHeight: CGFloat { topInset + height + bottomInset }

    static func cellFrame(column: Int, row: Int, containerWidth: CGFloat) -> CGRect {
        let originX = (containerWidth - width) / 2
        let columnStride = cellSize + columnSpacing
        let rowStride = cellSize + rowSpacing
        return CGRect(
            x: originX + CGFloat(column) * columnStride,
            y: topInset + CGFloat(row) * rowStride,
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
