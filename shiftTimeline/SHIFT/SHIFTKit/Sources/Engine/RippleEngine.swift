import Foundation
import Models

// MARK: - RippleEngine

/// A stateless engine that propagates a time-delta change across a set of
/// time blocks.
///
/// ## Pipeline
/// 1. **Dependency resolution** — determines which blocks are explicit
///    downstream dependents of the changed block (via an adjacency list or the
///    legacy temporal fallback).
/// 2. **Bounded shift propagation** — shifts the changed block, every
///    subsequent Fluid block **up to the first Pinned block encountered**, and
///    every explicit dependent by `delta`. Pinned blocks act as a **hard wall**
///    for positional ripple: nothing past the first downstream Pinned block is
///    moved by positional propagation. Explicit dependents (declared via
///    `adjacency` / `dependsOn`) still propagate across the wall because they
///    are a user-declared contract.
///
/// Collision detection and compression are handled by the injected
/// ``CollisionDetector`` and ``CompressionCalculator`` (used by callers after
/// this method returns). When positional ripple pushes a Fluid block past a
/// Pinned block's start (the "squeeze" case), the Fluid block is still shifted
/// and the resulting overlap is reported by ``CollisionDetector``.
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
    /// Snapshot block state via `BlockSnapshot` before calling if undo/redo is needed.
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
        let dependentIDs: Set<UUID>
        if let adjacency {
            switch dependencyResolver.resolve(adjacency: adjacency, from: changedBlockID) {
            case .success(let ids):
                dependentIDs = ids
            case .failure:
                return RippleResult(blocks: sorted, status: .circularDependency)
            }
        } else {
            dependentIDs = []
        }

        // --- Stage 2 set-up: Bounded positional ripple ---
        // Walk forward; include Fluid blocks until the first Pinned wall. Explicit dependents are unioned on top.
        var subsequentFluidIDs: Set<UUID> = []
        if changedIndex + 1 < sorted.count {
            for i in (changedIndex + 1)..<sorted.count {
                if sorted[i].isPinned { break }
                subsequentFluidIDs.insert(sorted[i].id)
            }
        }
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
