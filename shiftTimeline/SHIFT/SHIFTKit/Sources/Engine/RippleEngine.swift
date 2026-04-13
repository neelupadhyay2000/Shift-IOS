import Foundation
import Models

// MARK: - RippleEngine

/// A stateless engine that propagates a time-delta change across a set of
/// time blocks.
///
/// ## Pipeline
/// 1. **Dependency resolution** — determines which blocks are downstream of the
///    changed block (via temporal ordering or an explicit adjacency list).
/// 2. **Shift propagation** — shifts the changed block and all downstream Fluid
///    blocks by `delta`.
///
/// Collision detection and compression are handled by the injected
/// ``CollisionDetector`` and ``CompressionCalculator`` (used by callers after
/// this method returns).
public struct RippleEngine: Sendable {
    private let dependencyResolver: DependencyResolver
    private let collisionDetector: CollisionDetector
    private let compressionCalculator: CompressionCalculator

    public init(
        dependencyResolver: DependencyResolver = .init(),
        collisionDetector: CollisionDetector = .init(),
        compressionCalculator: CompressionCalculator = .init()
    ) {
        self.dependencyResolver = dependencyResolver
        self.collisionDetector = collisionDetector
        self.compressionCalculator = compressionCalculator
    }

    /// Recalculates the timeline after a block's scheduled time changes.
    ///
    /// - Parameters:
    ///   - blocks: All time blocks in the timeline.
    ///   - changedBlockID: The ID of the block whose time changed.
    ///   - delta: The time shift in seconds (positive = later, negative = earlier).
    ///   - adjacency: An optional explicit forward adjacency list. When provided,
    ///     dependency resolution uses this graph instead of temporal ordering.
    /// - Returns: A ``RippleResult`` whose blocks are always sorted by
    ///   `scheduledStart`.
    ///
    /// ## Mutation Semantics
    ///
    /// `TimeBlockModel` is a reference-type SwiftData `@Model`. This method
    /// **mutates `scheduledStart` directly on the passed-in instances** so that
    /// SwiftData's change-tracking picks up the modifications automatically.
    /// The ``RippleResult/blocks`` array holds references to the same (now-mutated)
    /// objects — it is **not** a set of independent copies.
    ///
    /// Callers that need undo/redo support should **snapshot** the relevant
    /// properties (e.g. via `BlockSnapshot`) *before* calling this method.
    public func recalculate(
        blocks: [TimeBlockModel],
        changedBlockID: UUID,
        delta: TimeInterval,
        adjacency: [UUID: [UUID]]? = nil
    ) -> RippleResult {
        let sorted = blocks.sorted { $0.scheduledStart < $1.scheduledStart }

        guard delta != 0 else {
            return RippleResult(blocks: sorted, status: .clean)
        }

        guard let changedIndex = sorted.firstIndex(where: { $0.id == changedBlockID }) else {
            return RippleResult(blocks: sorted, status: .clean)
        }

        // Pinned blocks cannot be shifted.
        if sorted[changedIndex].isPinned {
            return RippleResult(blocks: sorted, status: .pinnedBlockCannotShift)
        }

        // --- Stage 1: Dependency Resolution ---
        let depResult: Result<Set<UUID>, SHIFTError>
        if let adjacency {
            depResult = dependencyResolver.resolve(adjacency: adjacency, from: changedBlockID)
        } else {
            // Pass the already-sorted array to avoid a redundant sort inside resolve().
            depResult = dependencyResolver.resolve(sortedBlocks: sorted, shiftedBlockID: changedBlockID)
        }

        let dependentIDs: Set<UUID>
        switch depResult {
        case .success(let ids):
            dependentIDs = ids
        case .failure:
            return RippleResult(blocks: sorted, status: .circularDependency)
        }

        // Merge: blocks that should shift are subsequent Fluid blocks OR
        // explicit dependents (that are also Fluid).
        let subsequentFluidIDs: Set<UUID> = Set(
            sorted[(changedIndex + 1)...].filter { !$0.isPinned }.map(\.id)
        )
        let shiftableIDs = subsequentFluidIDs.union(dependentIDs)

        // --- Stage 2: Shift Propagation ---

        // Shift the changed block itself.
        let changedBlock = sorted[changedIndex]
        if delta > 0 {
            changedBlock.scheduledStart = changedBlock.scheduledStart.addingTimeInterval(delta)
        } else {
            changedBlock.scheduledStart = max(
                changedBlock.originalStart,
                changedBlock.scheduledStart.addingTimeInterval(delta)
            )
        }

        // Shift all shiftable blocks (skipping pinned).
        for block in sorted where shiftableIDs.contains(block.id) && !block.isPinned {
            if delta > 0 {
                block.scheduledStart = block.scheduledStart.addingTimeInterval(delta)
            } else {
                block.scheduledStart = max(
                    block.originalStart,
                    block.scheduledStart.addingTimeInterval(delta)
                )
            }
        }

        return RippleResult(blocks: sorted, status: .clean)
    }
}
