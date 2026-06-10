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
    /// Deterministic timeline ordering: `scheduledStart` ascending; on a tie,
    /// Fluid before Pinned (matching collision semantics — a fluid block at a
    /// pinned block's instant is *at* the wall, not past it); final tie broken
    /// by `id` so equal-start blocks order identically on every run. A bare
    /// `scheduledStart <` sort is ambiguous for ties, which made the shift set
    /// nondeterministic.
    public static func canonicalOrder(_ a: TimeBlockModel, _ b: TimeBlockModel) -> Bool {
        if a.scheduledStart != b.scheduledStart { return a.scheduledStart < b.scheduledStart }
        if a.isPinned != b.isPinned { return !a.isPinned }
        return a.id.uuidString < b.id.uuidString
    }

    public func recalculate(
        blocks: [TimeBlockModel],
        changedBlockID: UUID,
        delta: TimeInterval,
        adjacency: [UUID: [UUID]]? = nil
    ) -> RippleResult {
        let sorted = blocks.sorted(by: Self.canonicalOrder)

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
        //
        // Only an *explicit* adjacency list contributes "dependents" that can
        // cross the pinned wall. The temporal fallback would otherwise treat
        // every subsequent block as a downstream dependent, defeating the
        // bounded-ripple rule below.
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
        //
        // Walk forward from the changed block; include subsequent Fluid blocks
        // until we hit a Pinned block, which acts as a hard wall and halts
        // positional ripple. Explicit dependents (if any) are unioned on top
        // and may legitimately cross the wall.
        var subsequentFluidIDs: Set<UUID> = []
        if changedIndex + 1 < sorted.count {
            for i in (changedIndex + 1)..<sorted.count {
                if sorted[i].isPinned { break }
                subsequentFluidIDs.insert(sorted[i].id)
            }
        }
        // Same-instant siblings: a fluid block sharing the changed block's
        // exact start may sort *before* it (tie broken by id), yet it is not
        // upstream — it is concurrent. It must ripple with the changed block,
        // or it gets silently left behind and overlaps the shifted timeline.
        let changedStart = sorted[changedIndex].scheduledStart
        var siblingIndex = changedIndex - 1
        while siblingIndex >= 0, sorted[siblingIndex].scheduledStart == changedStart {
            if !sorted[siblingIndex].isPinned {
                subsequentFluidIDs.insert(sorted[siblingIndex].id)
            }
            siblingIndex -= 1
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

    /// The full commit pipeline: shift propagation (``recalculate``) followed by
    /// collision detection and compression — the same four stages
    /// ``ShiftPreviewGenerator`` projects, applied to the live models.
    ///
    /// **Every commit path must use this, not ``recalculate`` alone.** The
    /// preview the user confirms includes collision + compression resolution;
    /// committing only the bounded shift leaves fluid blocks overlapping pinned
    /// walls and `requiresReview` flags stale — the committed timeline diverges
    /// from the confirmed preview.
    ///
    /// Mutates the passed-in `TimeBlockModel` instances in place (see
    /// ``recalculate`` for the mutation contract). Returns:
    /// - `.clean` — shift applied, no overlap with any pinned block.
    /// - `.hasCollisions` — overlaps occurred and were resolved by compressing
    ///   the trapped fluid run to fit before the wall; `compressedBlockIDs`
    ///   names every block whose start or duration changed in resolution.
    /// - `.impossible` — minimum durations exceed the available gap; trapped
    ///   blocks are parked at `minimumDuration` and flagged `requiresReview`.
    /// - early-exit statuses (`.pinnedBlockCannotShift`, `.circularDependency`)
    ///   pass through unchanged with no mutation.
    public func applyShift(
        blocks: [TimeBlockModel],
        changedBlockID: UUID,
        delta: TimeInterval,
        adjacency: [UUID: [UUID]]? = nil
    ) -> RippleResult {
        let shifted = recalculate(
            blocks: blocks,
            changedBlockID: changedBlockID,
            delta: delta,
            adjacency: adjacency
        )
        switch shifted.status {
        case .pinnedBlockCannotShift, .circularDependency:
            return shifted
        case .clean, .hasCollisions, .impossible:
            break
        }
        guard delta != 0 else { return shifted }

        // Stage 3: collision detection (also re-stamps requiresReview on every
        // fluid block, clearing stale flags from previously resolved overlaps).
        let sorted = blocks.sorted(by: Self.canonicalOrder)
        let collisions = collisionDetector.detect(sortedBlocks: sorted)
        guard !collisions.isEmpty else {
            return RippleResult(blocks: sorted, status: .clean)
        }

        // Stage 4: compress each trapped run to fit before its wall. Snapshot
        // first so compressedBlockIDs reports exactly what resolution changed.
        let startsBefore = Dictionary(uniqueKeysWithValues: sorted.map { ($0.id, $0.scheduledStart) })
        let durationsBefore = Dictionary(uniqueKeysWithValues: sorted.map { ($0.id, $0.duration) })

        var status: RippleStatus = .hasCollisions
        for collision in collisions {
            if compressionCalculator.compress(sortedBlocks: sorted, collision: collision).status == .impossible {
                status = .impossible
            }
        }

        let compressedIDs = Set(
            sorted.filter {
                startsBefore[$0.id] != $0.scheduledStart || durationsBefore[$0.id] != $0.duration
            }.map(\.id)
        )

        return RippleResult(
            blocks: sorted,
            collisions: collisions.map(\.fluidBlockID),
            compressedBlockIDs: compressedIDs,
            status: status
        )
    }
}
