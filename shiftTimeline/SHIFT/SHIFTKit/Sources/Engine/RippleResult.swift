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

/// Result of a ripple-engine recalculation. `blocks` is always sorted by `scheduledStart` (enforced in `init`).
/// `blocks` holds references to already-mutated `TimeBlockModel` instances — not independent copies.
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
