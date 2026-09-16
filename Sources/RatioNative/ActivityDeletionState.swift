import Foundation
import RatioCore

struct ActivityDeleteGestureState {
    private enum Direction { case undecided, horizontal, ignored }

    private(set) var offset: CGFloat = 0
    private var direction = Direction.undecided
    private var didCommit = false

    /// Returns true only for the update that first crosses the deletion threshold.
    mutating func update(translation: CGSize, rowWidth: CGFloat) -> Bool {
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
        guard !didCommit else { return }
        offset = 0
        direction = .undecided
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
        case let .undo(deletion): return .undo(deletion.id)
        }
    }
}

struct PendingActivityDeletion: Identifiable, Equatable {
    let id: UUID
    let deletion: ActivityDeletion
    let isDemo: Bool
    let positions: [AppModel.ActivityFilter: Int]
    let expiresAtUptime: TimeInterval
}

struct ActivityDeletionState {
    static let undoDuration: TimeInterval = 6
    private(set) var pending: [PendingActivityDeletion] = []

    @discardableResult
    mutating func insert(
        _ deletion: ActivityDeletion,
        isDemo: Bool,
        positions: [AppModel.ActivityFilter: Int],
        atUptime uptime: TimeInterval,
        id: UUID = UUID()
    ) -> PendingActivityDeletion {
        let deletion = PendingActivityDeletion(
            id: id,
            deletion: deletion,
            isDemo: isDemo,
            positions: positions.mapValues { max(0, $0) },
            expiresAtUptime: uptime + Self.undoDuration
        )
        pending.append(deletion)
        return deletion
    }

    mutating func expire(atUptime uptime: TimeInterval) {
        pending.removeAll { uptime >= $0.expiresAtUptime }
    }

    mutating func take(id: UUID) -> PendingActivityDeletion? {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return nil }
        return pending.remove(at: index)
    }

    mutating func removeAll(isDemo: Bool) -> [PendingActivityDeletion] {
        let removed = pending.filter { $0.isDemo == isDemo }
        pending.removeAll { $0.isDemo == isDemo }
        return removed
    }

    func rows(
        activities: [ActivityTotal],
        isDemo: Bool,
        filter: AppModel.ActivityFilter
    ) -> [TodayActivityRow] {
        var rows = activities.map(TodayActivityRow.activity)
        let placeholders = pending.enumerated().compactMap {
            pair -> (offset: Int, deletion: PendingActivityDeletion, position: Int)? in
            let (offset, deletion) = pair
            guard deletion.isDemo == isDemo, let position = deletion.positions[filter] else { return nil }
            return (offset, deletion, position)
        }
            .sorted {
                if $0.position == $1.position { return $0.offset < $1.offset }
                return $0.position < $1.position
            }
        for placeholder in placeholders {
            rows.insert(.undo(placeholder.deletion), at: min(placeholder.position, rows.count))
        }
        return rows
    }
}
