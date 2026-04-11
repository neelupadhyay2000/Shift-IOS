import Foundation

// MARK: - Collision

/// Describes a temporal overlap between a Fluid block and a Pinned block.
///
/// A collision occurs when a Fluid block's scheduled time window extends into
/// the start of a downstream Pinned block. The engine uses this value to drive
/// compression (Stage 4) and to flag blocks for user review.
public struct Collision: Sendable, Equatable {
    /// The ID of the Fluid block that is running over its boundary.
    public let fluidBlockID: UUID

    /// The ID of the Pinned block that the Fluid block collides with.
    public let pinnedBlockID: UUID

    /// How many whole minutes the Fluid block overlaps into the Pinned block.
    public let overlapMinutes: Int

    public init(fluidBlockID: UUID, pinnedBlockID: UUID, overlapMinutes: Int) {
        self.fluidBlockID = fluidBlockID
        self.pinnedBlockID = pinnedBlockID
        self.overlapMinutes = overlapMinutes
    }
}
