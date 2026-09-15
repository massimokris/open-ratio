import SwiftUI
import RatioCore

@MainActor
final class AppModel: ObservableObject {
    enum Page: String, CaseIterable { case today = "Today", history = "History", preferences = "Preferences" }
    enum ActivityFilter: String, CaseIterable { case all = "All activity", unclassified = "Unclassified" }
    enum Appearance: String, CaseIterable {
        case system = "System", light = "Light", dark = "Dark"
        var colorScheme: ColorScheme? { self == .system ? nil : (self == .dark ? .dark : .light) }
    }
    @Published var session = RatioSession()
    @Published var page: Page = .today
    @Published var filter: ActivityFilter = .all
    @Published var tourPresented = false
    @Published var now = Date()
    @Published var appearance: Appearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") }
    }
    private var timer: Timer?

    init() {
        appearance = Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "System") ?? .system
        if ProcessInfo.processInfo.arguments.contains("--demo") { startDemo() }
        let heartbeat = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // Explicit main/common scheduling also advances while native menus track input.
        RunLoop.main.add(heartbeat, forMode: .common)
        timer = heartbeat
    }
    var today: String { ActivityFormatting.dayIdentifier(for: now) }
    var summary: DaySummary { session.ledger.summary(on: today) }
    var activeSource: ActivitySource? { session.activeSource }
    var activeCategory: ActivityCategory? { activeSource.flatMap { session.ledger.categories[$0.id] } }
    var unclassifiedCount: Int { summary.activities.filter { $0.category == nil }.count }
    var activityRows: [ActivityTotal] {
        summary.activities.filter { filter == .all || $0.category == nil }.sorted {
            if ($0.id == activeSource?.id) != ($1.id == activeSource?.id) { return $0.id == activeSource?.id }
            return $0.seconds == $1.seconds ? $0.source.name < $1.source.name : $0.seconds > $1.seconds
        }
    }
    var menuRatio: String {
        guard let percentage = summary.createPercentage else { return "— : —" }
        let create = Int(percentage.rounded())
        return "\(create) : \(100 - create)"
    }
    var statusText: String {
        if session.isPaused { return "Tracking paused" }
        if session.isDemo { return "Demo is running" }
        return activeSource == nil ? "Waiting for activity" : "Tracking activity"
    }
    func tick() {
        now = Date()
        session.advanceDemo(seconds: 1, day: today)
    }
    func classify(_ source: ActivitySource, as category: ActivityCategory?) { session.classify(source, as: category) }
    func togglePause() { session.setPaused(!session.isPaused) }
    func startDemo() { session.enterDemo(day: today); page = .today; filter = .all }
    func resetDemo() { session.resetDemo(day: today); filter = .all }
    func exitDemo() { session.exitDemo(); filter = .all }
    func selectDemoSource(_ source: ActivitySource) { session.selectDemoSource(source) }
    func showTour() { startDemo(); tourPresented = true }
}
