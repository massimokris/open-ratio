import Foundation

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

    public init(liveLedger: ActivityLedger = ActivityLedger()) { self.liveLedger = liveLedger }
    public var ledger: ActivityLedger { isDemo ? demoLedger : liveLedger }
    public var isPaused: Bool { isDemo ? isDemoPaused : isLivePaused }
    public var activeSource: ActivitySource? { isDemo ? demoSource : liveSource }
    public var canUndoReset: Bool { !isDemo && removedDay != nil }
    public var availableDemoSources: [ActivitySource] { demoSeed.map { $0.sources.values.sorted { $0.name < $1.name } } ?? DemoData.sources }

    /// The outgoing observation owns elapsed time; the current source starts at this instant.
    public mutating func observe(_ observation: ActivityObservation, calendar: Calendar = .current) {
        defer {
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

    public mutating func setSystemActive(_ active: Bool) {
        isSystemActive = active
        previousObservation = nil
    }
    public mutating func recordLive(seconds: TimeInterval, source: ActivitySource, day: String) {
        guard !isDemo, !isLivePaused, isSystemActive else { return }
        liveSource = source
        liveLedger.record(seconds: seconds, source: source, day: day)
    }
    public mutating func enterDemo(day: String) {
        guard !isDemo else { return }
        previousObservation = nil
        isDemo = true
        demoSeed = nil
        demoSeedSource = nil
        resetDemo(day: day)
    }
    /// Custom instructional fixtures share the same isolated demo lifecycle.
    public mutating func enterDemo(ledger: ActivityLedger, activeSource: ActivitySource?) {
        previousObservation = nil
        isDemo = true
        demoSeed = ledger
        demoSeedSource = activeSource
        demoLedger = ledger
        demoSource = activeSource
        isDemoPaused = false
    }
    public mutating func resetDemo(day: String) {
        guard isDemo else { return }
        demoLedger = demoSeed ?? DemoData.ledger(day: day)
        demoSource = demoSeed == nil ? DemoData.sources.first : demoSeedSource
        isDemoPaused = false
    }
    public mutating func selectDemoSource(_ source: ActivitySource) {
        guard isDemo, availableDemoSources.contains(source) else { return }
        demoSource = source
    }
    public mutating func advanceDemo(seconds: TimeInterval, day: String) {
        guard isDemo, !isDemoPaused, let source = demoSource else { return }
        demoLedger.record(seconds: seconds, source: source, day: day)
    }
    public mutating func exitDemo() { isDemo = false; previousObservation = nil }
}

public enum DemoData {
    public static let sources: [ActivitySource] = [
        ActivitySource(id: "demo.figma", name: "Figma"),
        ActivitySource(id: "demo.code", name: "Visual Studio Code"),
        ActivitySource(id: "demo.notes", name: "Notes"),
        ActivitySource(id: "demo.youtube", name: "youtube.com", kind: .website),
        ActivitySource(id: "demo.spotify", name: "Spotify"),
        ActivitySource(id: "demo.x", name: "x.com", kind: .website),
        ActivitySource(id: "demo.slack", name: "Slack"),
        ActivitySource(id: "demo.finder", name: "Finder")
    ]
    public static func ledger(day: String) -> ActivityLedger {
        var ledger = ActivityLedger()
        let minutes: [Double] = [68, 49, 13, 46, 16, 12, 14, 8]
        for (index, source) in sources.enumerated() {
            ledger.record(seconds: minutes[index] * 60, source: source, day: day)
            if index < 3 { ledger.classify(source, as: .create) }
            else if index < 6 { ledger.classify(source, as: .consume) }
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
