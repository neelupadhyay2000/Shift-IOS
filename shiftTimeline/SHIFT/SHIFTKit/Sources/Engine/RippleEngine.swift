import Foundation
import Models

// MARK: - Dependencies

/// Resolves ordering dependencies between time blocks.
public struct DependencyResolver: Sendable {
    public init() {}
}

/// Calculates how blocks can be compressed toward their minimum duration.
public struct CompressionCalculator: Sendable {
    public init() {}
}

// MARK: - RippleEngine

/// A stateless engine that propagates a time-delta change across a set of
/// time blocks.
///
/// Currently handles forward/backward shifting of Fluid blocks and pinned-block
/// rejection. Collision detection and compression are planned for future iterations
/// and will use the injected ``DependencyResolver``, ``CollisionDetector``, and
/// ``CompressionCalculator``.
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
    /// - Returns: A ``RippleResult`` whose blocks are always sorted by
    ///   `scheduledStart` (enforced by ``RippleResult/init``).
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
    ///
    /// - Note: The method pre-sorts `blocks` so the shift algorithm can rely on
    ///   positional indexing. ``RippleResult`` applies its own sort on
    ///   construction, guaranteeing the ordering contract even if a future code
    ///   path skips the local sort.
    public func recalculate(
        blocks: [TimeBlockModel],
        changedBlockID: UUID,
        delta: TimeInterval
    ) -> RippleResult {
        // Pre-sort so the algorithm can address blocks by positional index.
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

        // Shift the changed block itself, clamped to originalStart for negative delta.
        let changedBlock = sorted[changedIndex]
        if delta > 0 {
            changedBlock.scheduledStart = changedBlock.scheduledStart.addingTimeInterval(delta)
        } else {
            changedBlock.scheduledStart = max(
                changedBlock.originalStart,
                changedBlock.scheduledStart.addingTimeInterval(delta)
            )
        }

        // Shift all subsequent Fluid (non-pinned) blocks by delta.
        for index in (changedIndex + 1)..<sorted.count where !sorted[index].isPinned {
            let block = sorted[index]
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
