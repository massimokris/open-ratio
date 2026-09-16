import Foundation

public enum ActivityCategory: String, Codable, CaseIterable, Identifiable {
    case create, consume
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public struct ActivitySource: Codable, Hashable, Identifiable {
    public enum Kind: String, Codable { case application, website }
    public var id: String
    public var name: String
    public var kind: Kind
    public init(id: String, name: String, kind: Kind = .application) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

public struct ActivityTotal: Identifiable, Equatable {
    public var source: ActivitySource
    public var seconds: TimeInterval
    public var category: ActivityCategory?
    public var id: String { source.id }
}

public struct DaySummary: Identifiable, Equatable {
    public var day: String
    public var activities: [ActivityTotal]
    public var id: String { day }
    public var createSeconds: TimeInterval { activities.filter { $0.category == .create }.reduce(0) { $0 + $1.seconds } }
    public var consumeSeconds: TimeInterval { activities.filter { $0.category == .consume }.reduce(0) { $0 + $1.seconds } }
    public var unclassifiedSeconds: TimeInterval { activities.filter { $0.category == nil }.reduce(0) { $0 + $1.seconds } }
    public var totalSeconds: TimeInterval { activities.reduce(0) { $0 + $1.seconds } }
    public var createPercentage: Double? {
        let classified = createSeconds + consumeSeconds
        return classified > 0 ? createSeconds / classified * 100 : nil
    }
}

/// Retained source totals and remembered categories. Day labels are assigned at capture time.
public struct ActivityLedger: Codable, Equatable {
    public private(set) var sources: [String: ActivitySource] = [:]
    public private(set) var days: [String: [String: TimeInterval]] = [:]
    public private(set) var categories: [String: ActivityCategory] = [:]
    public init() {}

    public func summary(on day: String) -> DaySummary {
        let activities = (days[day] ?? [:]).compactMap { sourceID, seconds -> ActivityTotal? in
            guard let source = sources[sourceID] else { return nil }
            return ActivityTotal(source: source, seconds: seconds, category: categories[sourceID])
        }.sorted { lhs, rhs in
            lhs.seconds == rhs.seconds ? lhs.source.name < rhs.source.name : lhs.seconds > rhs.seconds
        }
        return DaySummary(day: day, activities: activities)
    }

    public var history: [DaySummary] { days.keys.sorted(by: >).map { summary(on: $0) } }

    public mutating func record(seconds: TimeInterval, source: ActivitySource, day: String) {
        guard seconds.isFinite, seconds > 0 else { return }
        sources[source.id] = source
        days[day, default: [:]][source.id, default: 0] += seconds
    }

    /// Removes one source's recorded time from a day while retaining its identity and category.
    @discardableResult
    public mutating func removeActivity(for source: ActivitySource, on day: String) -> ActivityTotal? {
        guard let recordedSource = sources[source.id],
              let seconds = days[day]?.removeValue(forKey: source.id) else { return nil }
        if days[day]?.isEmpty == true { days.removeValue(forKey: day) }
        return ActivityTotal(source: recordedSource, seconds: seconds, category: categories[source.id])
    }

    /// Adds removed time back without replacing newer source metadata or category choices.
    public mutating func restoreActivity(_ activity: ActivityTotal, on day: String) {
        record(seconds: activity.seconds, source: sources[activity.id] ?? activity.source, day: day)
    }

    /// Clears one recorded day while retaining remembered categories and earlier days.
    @discardableResult
    public mutating func removeActivity(on day: String) -> DaySummary {
        let removed = summary(on: day)
        days.removeValue(forKey: day)
        return removed
    }

    public mutating func classify(_ source: ActivitySource, as category: ActivityCategory?) {
        sources[source.id] = source
        categories[source.id] = category
    }
}
