import AppKit
import SwiftUI
import RatioCore

@MainActor
final class AppModel: ObservableObject {
    enum Page: String, CaseIterable { case today = "Today", history = "History", preferences = "Preferences" }
    enum ActivityFilter: String, CaseIterable { case all = "All activity", unclassified = "Unclassified" }
    enum Appearance: String, CaseIterable {
        case light = "Light", dark = "Dark"
        var colorScheme: ColorScheme { self == .dark ? .dark : .light }
    }
    @Published var session = RatioSession()
    @Published var page: Page = .today
    @Published var filter: ActivityFilter = .all
    @Published var now = Date()
    @Published private(set) var storageNotice: String?
    @Published private(set) var isReferenceDemo = false
    let browserTracking = BrowserTrackingCoordinator()
    let dataDirectory: URL
    @Published var appearance: Appearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") }
    }
    private var timer: Timer?
    private let activityStore: ActivityStore
    private let foregroundMonitor = ForegroundActivityMonitor()
    private var terminationObserver: NSObjectProtocol?
    private var lastSavedLedger = ActivityLedger()
    private var lastSaveUptime: TimeInterval = 0
    private var persistenceBlocked = false
    private var recoveryNotice: String?

    init() {
        let override = ProcessInfo.processInfo.environment["RATIO_NATIVE_DATA_DIR"]
        dataDirectory = override.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("RatioNative", isDirectory: true)
        activityStore = ActivityStore(directory: dataDirectory)
        let savedAppearance = UserDefaults.standard.string(forKey: "appearance")
        // Resolve the legacy System choice once so every saved preference is Light or Dark.
        appearance = savedAppearance.flatMap(Appearance.init(rawValue:))
            ?? (NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light)
        UserDefaults.standard.set(appearance.rawValue, forKey: "appearance")
        do {
            let loaded = try activityStore.load()
            session = RatioSession(liveLedger: loaded.ledger)
            lastSavedLedger = loaded.ledger
            recoveryNotice = loaded.notice
            storageNotice = loaded.notice
        } catch {
            persistenceBlocked = true
            storageNotice = "Activity could not be loaded: \(error.localizedDescription) Your original files are retained. Resolve the problem in the data folder and reopen Ratio Native; new activity is only held in memory."
        }
        if ProcessInfo.processInfo.arguments.contains("--reference-demo") { startReferenceDemo() }
        else if ProcessInfo.processInfo.arguments.contains("--demo") { startDemo() }
        browserTracking.onChange = { [weak self] in self?.refreshTracking() }
        foregroundMonitor.onForegroundApplicationChange = { [weak self] application in
            guard let self else { return }
            self.browserTracking.foregroundChanged(self.capturesWebsites ? application : nil)
        }
        foregroundMonitor.sourceResolver = { [weak self] application, fallback in
            guard let self, self.capturesWebsites else { return fallback }
            return self.browserTracking.resolve(application, fallingBackTo: fallback)
        }
        foregroundMonitor.onObservation = { [weak self] in self?.receive($0) }
        foregroundMonitor.onSystemActiveChange = { [weak self] active in
            guard let self else { return }
            self.session.setSystemActive(active)
            if !active { self.browserTracking.foregroundChanged(nil) }
            if !active { self.saveActivity() }
        }
        foregroundMonitor.start()
        let heartbeat = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(heartbeat, forMode: .common)
        timer = heartbeat
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshTracking()
                self?.saveActivity()
                self?.foregroundMonitor.stop()
                self?.timer?.invalidate()
            }
        }
    }
    var today: String { ActivityFormatting.dayIdentifier(for: now) }
    var summary: DaySummary { session.ledger.summary(on: today) }
    var activeSource: ActivitySource? { session.activeSource }
    var activeCategory: ActivityCategory? { activeSource.flatMap { session.ledger.categories[$0.id] } }
    var unclassifiedCount: Int { summary.activities.filter { $0.category == nil }.count }
    var activityRows: [ActivityTotal] {
        summary.activities.filter { filter == .all || $0.category == nil }.sorted {
            if isReferenceDemo {
                return (ReferenceDemo.sourceOrder.firstIndex(of: $0.id) ?? Int.max)
                    < (ReferenceDemo.sourceOrder.firstIndex(of: $1.id) ?? Int.max)
            }
            if ($0.id == activeSource?.id) != ($1.id == activeSource?.id) { return $0.id == activeSource?.id }
            return $0.seconds == $1.seconds ? $0.source.name < $1.source.name : $0.seconds > $1.seconds
        }
    }
    var menuRatio: String {
        guard let percentage = summary.createPercentage else { return "—/—" }
        let create = Int(percentage.rounded())
        return "\(create)/\(100 - create)"
    }
    var indicatorPaused: Bool { session.isPaused || (!session.isDemo && (session.isLiveIdle || !session.isSystemActive)) }
    private var capturesWebsites: Bool { !session.isDemo && !session.isPaused && session.isSystemActive }
    var browserFallbackNotice: String? { capturesWebsites ? browserTracking.fallbackNotice : nil }
    var statusText: String {
        if session.isPaused { return "Tracking paused" }
        if session.isDemo { return "Demo is running" }
        if !session.isSystemActive { return "Session inactive" }
        if session.isLiveIdle { return "Idle · tracking suspended" }
        return browserFallbackNotice ?? (activeSource == nil ? "Waiting for activity" : "Tracking activity")
    }
    var canUndoReset: Bool { session.canUndoReset }

    func refreshTracking() { receive(foregroundMonitor.sample()) }
    private func receive(_ observation: ActivityObservation) {
        now = observation.date
        session.observe(observation)
        if observation.uptime - lastSaveUptime >= 5 { saveActivity() }
    }
    func tick() {
        refreshTracking()
        if !isReferenceDemo { session.advanceDemo(seconds: 1, day: today) }
    }
    func saveActivity() {
        guard !persistenceBlocked, session.liveLedger != lastSavedLedger else { return }
        do {
            try activityStore.save(session.liveLedger)
            lastSavedLedger = session.liveLedger
            lastSaveUptime = ProcessInfo.processInfo.systemUptime
            storageNotice = recoveryNotice
        } catch {
            storageNotice = "Activity could not be saved: \(error.localizedDescription) New activity remains in memory; Ratio Native will retry."
            lastSaveUptime = ProcessInfo.processInfo.systemUptime
        }
    }
    func classify(_ source: ActivitySource, as category: ActivityCategory?) {
        refreshTracking()
        session.classify(source, as: category)
        saveActivity()
    }
    func togglePause() {
        refreshTracking()
        session.setPaused(!session.isPaused)
        refreshTracking()
        saveActivity()
    }
    func startDemo() {
        refreshTracking()
        saveActivity()
        if isReferenceDemo { session.exitDemo(); isReferenceDemo = false }
        session.enterDemo(day: today)
        browserTracking.foregroundChanged(nil)
        page = .today
        filter = .all
    }
    private func startReferenceDemo() {
        refreshTracking()
        saveActivity()
        session.enterDemo(ledger: ReferenceDemo.ledger(day: today), activeSource: ReferenceDemo.activeSource)
        browserTracking.foregroundChanged(nil)
        isReferenceDemo = true
        page = .today
        filter = .all
    }
    func resetDemo() {
        if isReferenceDemo { startDemo() }
        else { session.resetDemo(day: today) }
        filter = .all
    }
    func exitDemo() {
        session.exitDemo()
        isReferenceDemo = false
        refreshTracking()
        filter = .all
    }
    func resetToday() {
        if session.isDemo { resetDemo(); return }
        refreshTracking()
        session.resetDay(today)
        refreshTracking()
        saveActivity()
        filter = .all
    }
    func undoResetToday() { refreshTracking(); session.undoReset(); saveActivity() }
    func selectDemoSource(_ source: ActivitySource) { session.selectDemoSource(source) }
}
