import Foundation
import Models

// MARK: - RippleStatus

/// Describes the outcome of a ripple recalculation pass.
public enum RippleStatus: String, Sendable {
    case clean
    case hasCollisions
    case impossible
    case pinnedBlockCannotShift
    case circularDependency
}

// MARK: - RippleResult

/// The result of a ripple-engine recalculation, containing the adjusted
/// blocks and an overall status.
///
/// **Ordering contract:** `blocks` are always sorted by `scheduledStart`
/// (ascending). The sort is enforced inside `init`, so every code path that
/// creates a ``RippleResult`` is guaranteed to honour this invariant.
///
/// ## Mutation Semantics
///
/// ``blocks`` holds **references** to the same `TimeBlockModel` instances
/// that were passed into ``RippleEngine/recalculate(blocks:changedBlockID:delta:)``.
/// Those instances have already been mutated in place before this result is
/// constructed — the array is provided for ordering and status context, not as
/// a set of independent copies.
///
/// The `collisions` and `compressedBlockIDs` fields are reserved for future
/// collision-detection and compression passes. They currently default to empty.
public struct RippleResult {
    public let blocks: [TimeBlockModel]
    public let collisions: [UUID]
    public let compressedBlockIDs: Set<UUID>
    public let status: RippleStatus

    public init(
        blocks: [TimeBlockModel],
        collisions: [UUID] = [],
        compressedBlockIDs: Set<UUID> = [],
        status: RippleStatus = .clean
    ) {
        self.blocks = blocks.sorted { $0.scheduledStart < $1.scheduledStart }
        self.collisions = collisions
        self.compressedBlockIDs = compressedBlockIDs
        self.status = status
    }
}
