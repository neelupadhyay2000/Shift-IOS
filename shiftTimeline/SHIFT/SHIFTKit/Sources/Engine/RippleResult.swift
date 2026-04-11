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
/// blocks, any detected collisions, compressed block IDs, and an overall status.
public struct RippleResult: @unchecked Sendable {
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
        self.blocks = blocks
        self.collisions = collisions
        self.compressedBlockIDs = compressedBlockIDs
        self.status = status
    }
}
