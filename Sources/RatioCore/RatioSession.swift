import Foundation

public enum ActivityDataset: Equatable {
    case live
    case demo
}

/// The exact activity removed by one row deletion, including its original dataset and day.
public struct ActivityDeletion: Equatable {
    public let day: String
    public let activity: ActivityTotal
    public let dataset: ActivityDataset
}

/// Owns separate real and fictional datasets, including independent pause and foreground state.
public struct RatioSession {
    public var liveLedger: ActivityLedger
    public private(set) var demoLedger = ActivityLedger()
    public private(set) var isDemo = false
    public private(set) var isLivePaused = false
    public private(set) var isSystemActive = true
    public private(set) var isLiveIdle = false
    private var isDemoPaused = false
    public var liveSource: ActivitySource?
    private var demoSource: ActivitySource?
    private var previousObservation: ActivityObservation?
    private var removedDay: DaySummary?
    private var demoSeed: ActivityLedger?
    private var demoSeedSource: ActivitySource?
    private var suppressedLiveSourceID: String?
    private var suppressedDemoSourceID: String?

    public init(liveLedger: ActivityLedger = ActivityLedger()) { self.liveLedger = liveLedger }
    public var ledger: ActivityLedger { isDemo ? demoLedger : liveLedger }
    public var currentDataset: ActivityDataset { isDemo ? .demo : .live }
    public var isPaused: Bool { isDemo ? isDemoPaused : isLivePaused }
    public var activeSource: ActivitySource? { isDemo ? demoSource : liveSource }
    public var isActiveSourceSuppressed: Bool {
        let suppressedSourceID = isDemo ? suppressedDemoSourceID : suppressedLiveSourceID
        guard let suppressedSourceID, let activeSource else { return false }
        return activeSource.id == suppressedSourceID
    }
    public var canUndoReset: Bool { !isDemo && removedDay != nil }
    public var availableDemoSources: [ActivitySource] { demoSeed.map { $0.sources.values.sorted { $0.name < $1.name } } ?? DemoData.sources }

    /// The outgoing observation owns elapsed time; the current source starts at this instant.
    public mutating func observe(_ observation: ActivityObservation, calendar: Calendar = .current) {
        defer {
            if let suppressedLiveSourceID, let source = observation.source,
               source.id != suppressedLiveSourceID {
                self.suppressedLiveSourceID = nil
            }
            previousObservation = observation
            liveSource = observation.source
            isLiveIdle = observation.idleSeconds >= 300
        }
        guard !isDemo, !isLivePaused, isSystemActive, let previous = previousObservation else { return }
        let elapsed = observation.uptime - previous.uptime
        let wallElapsed = observation.date.timeIntervalSince(previous.date)
        guard elapsed.isFinite, elapsed > 0, elapsed <= 10,
              wallElapsed.isFinite, wallElapsed > 0, abs(wallElapsed - elapsed) <= 2 else { return }
        guard previous.idleSeconds.isFinite, observation.idleSeconds.isFinite,
              previous.idleSeconds >= 0, observation.idleSeconds >= 0,
              let source = previous.source else { return }
        // Union the old input's remaining grace with time after the most recent new input.
        let graceEnd = min(elapsed, max(0, 300 - previous.idleSeconds))
        let recentInput = max(0, elapsed - observation.idleSeconds)
        let resumedStart = observation.idleSeconds < elapsed
            ? max(graceEnd, recentInput) : elapsed
        recordInterval(from: 0, to: graceEnd, source: source, date: previous.date,
                       wallPerSecond: wallElapsed / elapsed, calendar: calendar)
        recordInterval(from: resumedStart, to: elapsed, source: source, date: previous.date,
                       wallPerSecond: wallElapsed / elapsed, calendar: calendar)
    }

    private mutating func recordInterval(from start: TimeInterval, to end: TimeInterval,
                                         source: ActivitySource, date: Date,
                                         wallPerSecond: Double, calendar: Calendar) {
        guard end > start else { return }
        var cursor = date.addingTimeInterval(start * wallPerSecond)
        let finish = date.addingTimeInterval(end * wallPerSecond)
        while cursor < finish {
            guard let day = calendar.dateInterval(of: .day, for: cursor) else { return }
            let boundary = min(finish, day.end)
            guard boundary > cursor else { return }
            recordLive(seconds: boundary.timeIntervalSince(cursor) / wallPerSecond,
                       source: source, day: ActivityFormatting.dayIdentifier(for: cursor, calendar: calendar))
            cursor = boundary
        }
    }

    public mutating func classify(_ source: ActivitySource, as category: ActivityCategory?) {
        if isDemo { demoLedger.classify(source, as: category) }
        else { liveLedger.classify(source, as: category) }
    }
    public mutating func setPaused(_ paused: Bool) {
        if isDemo { isDemoPaused = paused } else { isLivePaused = paused; previousObservation = nil }
    }
    public mutating func resetDay(_ day: String) {
        guard !isDemo else { resetDemo(day: day); return }
        let removed = liveLedger.removeActivity(on: day)
        if !removed.activities.isEmpty { removedDay = removed }
        previousObservation = nil
    }
    public mutating func undoReset() {
        guard !isDemo, let removed = removedDay else { return }
        for activity in removed.activities {
            liveLedger.record(seconds: activity.seconds, source: activity.source, day: removed.day)
        }
        removedDay = nil
    }

    public mutating func deleteActivity(_ source: ActivitySource, on day: String) -> ActivityDeletion? {
        if isDemo {
            guard let activity = demoLedger.removeActivity(for: source, on: day) else { return nil }
            if demoSource?.id == source.id { suppressedDemoSourceID = source.id }
            return ActivityDeletion(day: day, activity: activity, dataset: .demo)
        }
        guard let activity = liveLedger.removeActivity(for: source, on: day) else { return nil }
        if liveSource?.id == source.id { suppressedLiveSourceID = source.id }
        return ActivityDeletion(day: day, activity: activity, dataset: .live)
    }

    public mutating func undoDelete(_ deletion: ActivityDeletion) {
        switch deletion.dataset {
        case .live:
            liveLedger.restoreActivity(deletion.activity, on: deletion.day)
        case .demo:
            demoLedger.restoreActivity(deletion.activity, on: deletion.day)
        }
    }

    public mutating func setSystemActive(_ active: Bool) {
        isSystemActive = active
        previousObservation = nil
    }
    public mutating func recordLive(seconds: TimeInterval, source: ActivitySource, day: String) {
        guard !isDemo, !isLivePaused, isSystemActive else { return }
        liveSource = source
        if let suppressedLiveSourceID {
            guard source.id != suppressedLiveSourceID else { return }
            self.suppressedLiveSourceID = nil
        }
        liveLedger.record(seconds: seconds, source: source, day: day)
    }
    public mutating func enterDemo(day: String) {
        guard !isDemo else { return }
        previousObservation = nil
        isDemo = true
        suppressedDemoSourceID = nil
        demoSeed = nil
        demoSeedSource = nil
        resetDemo(day: day)
    }
    /// Custom instructional fixtures share the same isolated demo lifecycle.
    public mutating func enterDemo(ledger: ActivityLedger, activeSource: ActivitySource?) {
        previousObservation = nil
        isDemo = true
        suppressedDemoSourceID = nil
        demoSeed = ledger
        demoSeedSource = activeSource
        demoLedger = ledger
        demoSource = activeSource
        isDemoPaused = false
    }
    public mutating func resetDemo(day: String) {
        guard isDemo else { return }
        suppressedDemoSourceID = nil
        demoLedger = demoSeed ?? DemoData.ledger(day: day)
        demoSource = demoSeed == nil ? DemoData.sources.first : demoSeedSource
        isDemoPaused = false
    }
    public mutating func selectDemoSource(_ source: ActivitySource) {
        guard isDemo, availableDemoSources.contains(source) else { return }
        if let suppressedDemoSourceID, source.id != suppressedDemoSourceID {
            self.suppressedDemoSourceID = nil
        }
        demoSource = source
    }
    public mutating func advanceDemo(seconds: TimeInterval, day: String) {
        guard isDemo, !isDemoPaused, let source = demoSource else { return }
        guard source.id != suppressedDemoSourceID else { return }
        demoLedger.record(seconds: seconds, source: source, day: day)
    }
    public mutating func exitDemo() {
        isDemo = false
        previousObservation = nil
        suppressedDemoSourceID = nil
    }
}

public enum DemoData {
    private enum PriorDayAllocation {
        case categoryShare(ActivityCategory, weight: Double)
        case unclassified(minutes: Double)

        var category: ActivityCategory? {
            switch self {
            case let .categoryShare(category, _): return category
            case .unclassified: return nil
            }
        }

        func minutes(create: Double, consume: Double) -> Double {
            switch self {
            case let .categoryShare(.create, weight): return create * weight
            case let .categoryShare(.consume, weight): return consume * weight
            case let .unclassified(minutes): return minutes
            }
        }
    }

    private struct SourceFixture {
        let source: ActivitySource
        let todayMinutes: Double
        let priorDayAllocation: PriorDayAllocation
    }

    /// Twenty-nine prior days span both categories and the grid's full intensity range.
    private static let priorDayCreatePercentages: [Double] = [
        70, 30, 80, 20, 60, 40, 90, 10, 50, 75,
        25, 65, 35, 85, 15, 55, 45, 95, 5, 100,
        0, 72, 28, 82, 18, 62, 38, 52, 48
    ]

    private static let sourceFixtures: [SourceFixture] = [
        SourceFixture(
            source: ActivitySource(id: "demo.figma", name: "Figma"),
            todayMinutes: 68,
            priorDayAllocation: .categoryShare(.create, weight: 0.52)
        ),
        SourceFixture(
            source: ActivitySource(id: "demo.code", name: "Visual Studio Code"),
            todayMinutes: 49,
            priorDayAllocation: .categoryShare(.create, weight: 0.33)
        ),
        SourceFixture(
            source: ActivitySource(id: "demo.notes", name: "Notes"),
            todayMinutes: 13,
            priorDayAllocation: .categoryShare(.create, weight: 0.15)
        ),
        SourceFixture(
            source: ActivitySource(id: "demo.youtube", name: "youtube.com", kind: .website),
            todayMinutes: 46,
            priorDayAllocation: .categoryShare(.consume, weight: 0.58)
        ),
        SourceFixture(
            source: ActivitySource(id: "demo.spotify", name: "Spotify"),
            todayMinutes: 16,
            priorDayAllocation: .categoryShare(.consume, weight: 0.27)
        ),
        SourceFixture(
            source: ActivitySource(id: "demo.x", name: "x.com", kind: .website),
            todayMinutes: 12,
            priorDayAllocation: .categoryShare(.consume, weight: 0.15)
        ),
        SourceFixture(
            source: ActivitySource(id: "demo.slack", name: "Slack"),
            todayMinutes: 14,
            priorDayAllocation: .unclassified(minutes: 8)
        ),
        SourceFixture(
            source: ActivitySource(id: "demo.finder", name: "Finder"),
            todayMinutes: 8,
            priorDayAllocation: .unclassified(minutes: 4)
        )
    ]
    public static let sources = sourceFixtures.map(\.source)

    public static func ledger(day: String) -> ActivityLedger {
        var ledger = ActivityLedger()
        for fixture in sourceFixtures {
            ledger.record(seconds: fixture.todayMinutes * 60, source: fixture.source, day: day)
            if let category = fixture.priorDayAllocation.category {
                ledger.classify(fixture.source, as: category)
            }
        }
        // Fictional prior days make history and the ratio grid explorable without
        // manufacturing live activity.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let components = day.split(separator: "-").compactMap { Int($0) }
        if components.count == 3,
           let date = calendar.date(from: DateComponents(year: components[0], month: components[1], day: components[2], hour: 12)) {
            for (offset, createPercentage) in priorDayCreatePercentages.enumerated() {
                guard let previousDate = calendar.date(byAdding: .day, value: -(offset + 1), to: date) else { continue }
                let previousDay = ActivityFormatting.dayIdentifier(for: previousDate, calendar: calendar)
                let classifiedMinutes = 120 + Double((offset % 5) * 15)
                let createMinutes = classifiedMinutes * createPercentage / 100
                let consumeMinutes = classifiedMinutes - createMinutes
                for fixture in sourceFixtures {
                    let minutes = fixture.priorDayAllocation.minutes(
                        create: createMinutes,
                        consume: consumeMinutes
                    )
                    ledger.record(seconds: minutes * 60, source: fixture.source, day: previousDay)
                }
            }
        }
        return ledger
    }
}

public enum ActivityFormatting {
    public static func dayIdentifier(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    public static func duration(_ seconds: TimeInterval) -> String {
        let safe = seconds.isFinite ? max(0, min(seconds, Double(Int.max / 2))) : 0
        let total = Int(safe)
        if total >= 3600 { return "\(total / 3600)h \((total % 3600) / 60)m" }
        if total >= 60 { return "\(total / 60)m" }
        return "\(total)s"
    }
    public static func percentage(_ percentage: Double?) -> String {
        percentage.map { String(format: "%.0f", $0) } ?? "—"
    }
}
