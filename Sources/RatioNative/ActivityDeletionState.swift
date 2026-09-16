import Foundation
import RatioCore

struct ActivityDeleteGestureState {
    private enum Direction { case undecided, horizontal, ignored }

    private(set) var offset: CGFloat = 0
    private(set) var suppressesControlActivation = false
    private var direction = Direction.undecided
    private var didCommit = false

    /// Returns true only for the update that first crosses the deletion threshold.
    mutating func update(translation: CGSize, rowWidth: CGFloat) -> Bool {
        // Drag callbacks only begin after SwiftUI's minimum distance. Keep nested
        // buttons inert through mouse-up so a swipe cannot also classify the row.
        suppressesControlActivation = true
        guard !didCommit, rowWidth.isFinite, rowWidth > 0 else { return false }
        if direction == .undecided {
            direction = translation.width > 0 && translation.width > abs(translation.height)
                ? .horizontal : .ignored
        }
        guard direction == .horizontal else { return false }
        offset = min(max(0, translation.width), rowWidth)
        guard offset >= rowWidth * 0.8 else { return false }
        didCommit = true
        return true
    }

    mutating func finish() {
        offset = 0
        direction = .undecided
        didCommit = false
    }

    mutating func resumeControlActivation() {
        suppressesControlActivation = false
    }
}

enum TodayActivityRow: Identifiable, Equatable {
    enum ID: Hashable {
        case activity(String)
        case undo(UUID)
    }

    case activity(ActivityTotal)
    case undo(PendingActivityDeletion)

    var id: ID {
        switch self {
        case let .activity(activity): return .activity(activity.id)
        case let .undo(pendingDeletion): return .undo(pendingDeletion.id)
        }
    }
}

struct PendingActivityDeletion: Identifiable, Equatable {
    let id: UUID
    let activityDeletion: ActivityDeletion
    let positions: [AppModel.ActivityFilter: Int]
    let expiresAtUptime: TimeInterval

    var sourceName: String { activityDeletion.activity.source.name }
}

struct ActivityDeletionState {
    static let undoDuration: TimeInterval = 6
    private(set) var pending: [PendingActivityDeletion] = []

    @discardableResult
    mutating func insert(
        _ deletion: ActivityDeletion,
        positions: [AppModel.ActivityFilter: Int],
        atUptime uptime: TimeInterval,
        id: UUID = UUID()
    ) -> PendingActivityDeletion {
        let pendingDeletion = PendingActivityDeletion(
            id: id,
            activityDeletion: deletion,
            positions: positions.mapValues { max(0, $0) },
            expiresAtUptime: uptime + Self.undoDuration
        )
        pending.append(pendingDeletion)
        return pendingDeletion
    }

    mutating func expire(atUptime uptime: TimeInterval) -> [PendingActivityDeletion] {
        let expired = pending.filter { uptime >= $0.expiresAtUptime }
        pending.removeAll { uptime >= $0.expiresAtUptime }
        return expired
    }

    mutating func take(id: UUID, atUptime uptime: TimeInterval) -> PendingActivityDeletion? {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return nil }
        guard uptime < pending[index].expiresAtUptime else {
            pending.remove(at: index)
            return nil
        }
        return pending.remove(at: index)
    }

    mutating func removeAll(dataset: ActivityDataset) -> [PendingActivityDeletion] {
        let removed = pending.filter { $0.activityDeletion.dataset == dataset }
        pending.removeAll { $0.activityDeletion.dataset == dataset }
        return removed
    }

    func rows(
        activities: [ActivityTotal],
        dataset: ActivityDataset,
        filter: AppModel.ActivityFilter
    ) -> [TodayActivityRow] {
        var rows = activities.map(TodayActivityRow.activity)
        let placeholders = pending.enumerated().compactMap {
            pair -> (offset: Int, pendingDeletion: PendingActivityDeletion, position: Int)? in
            let (offset, pendingDeletion) = pair
            guard pendingDeletion.activityDeletion.dataset == dataset,
                  let position = pendingDeletion.positions[filter] else { return nil }
            return (offset, pendingDeletion, position)
        }
            .sorted {
                if $0.position == $1.position { return $0.offset < $1.offset }
                return $0.position < $1.position
        }
        for placeholder in placeholders {
            rows.insert(.undo(placeholder.pendingDeletion), at: min(placeholder.position, rows.count))
        }
        return rows
    }

    func position(
        of activityID: String,
        activities: [ActivityTotal],
        dataset: ActivityDataset,
        filter: AppModel.ActivityFilter
    ) -> Int? {
        rows(activities: activities, dataset: dataset, filter: filter)
            .firstIndex { $0.id == .activity(activityID) }
    }
}
