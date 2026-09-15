import Foundation

/// Owns separate real and fictional datasets, including independent pause and foreground state.
public struct RatioSession {
    public var liveLedger: ActivityLedger
    public private(set) var demoLedger = ActivityLedger()
    public private(set) var isDemo = false
    public private(set) var isLivePaused = false
    private var isDemoPaused = false
    public var liveSource: ActivitySource?
    private var demoSource: ActivitySource?

    public init(liveLedger: ActivityLedger = ActivityLedger()) { self.liveLedger = liveLedger }
    public var ledger: ActivityLedger { isDemo ? demoLedger : liveLedger }
    public var isPaused: Bool { isDemo ? isDemoPaused : isLivePaused }
    public var activeSource: ActivitySource? { isDemo ? demoSource : liveSource }
    public var availableDemoSources: [ActivitySource] { DemoData.sources }

    public mutating func classify(_ source: ActivitySource, as category: ActivityCategory?) {
        if isDemo { demoLedger.classify(source, as: category) }
        else { liveLedger.classify(source, as: category) }
    }
    public mutating func setPaused(_ paused: Bool) {
        if isDemo { isDemoPaused = paused } else { isLivePaused = paused }
    }
    public mutating func recordLive(seconds: TimeInterval, source: ActivitySource, day: String) {
        guard !isDemo, !isLivePaused else { return }
        liveSource = source
        liveLedger.record(seconds: seconds, source: source, day: day)
    }
    public mutating func enterDemo(day: String) {
        guard !isDemo else { return }
        isDemo = true
        resetDemo(day: day)
    }
    public mutating func resetDemo(day: String) {
        guard isDemo else { return }
        demoLedger = DemoData.ledger(day: day)
        demoSource = DemoData.sources.first
        isDemoPaused = false
    }
    public mutating func selectDemoSource(_ source: ActivitySource) {
        guard isDemo, DemoData.sources.contains(source) else { return }
        demoSource = source
    }
    public mutating func advanceDemo(seconds: TimeInterval, day: String) {
        guard isDemo, !isDemoPaused, let source = demoSource else { return }
        demoLedger.record(seconds: seconds, source: source, day: day)
    }
    public mutating func exitDemo() { isDemo = false }
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
