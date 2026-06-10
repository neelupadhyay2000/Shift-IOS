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
        case .clean, .hasCollisions, .impossible, .exceedsAvailableSlack:
            break
        }
        guard delta != 0 else { return shifted }

        return resolveCollisions(blocks: blocks)
    }

    // MARK: - Live extension (extend the active block, don't move it)

    /// The largest delta ``applyExtension`` can absorb for the given active
    /// block, or `nil` when no pinned block sits downstream (unbounded).
    ///
    /// - Wall immediately next: the slack is the gap between the active
    ///   block's end and the wall's start (an extension may grow into a gap).
    /// - Trapped fluid run before the wall: the run shifts with the extension
    ///   and is then compressed toward minimum durations, so the slack is
    ///   `wall.start − run.start − Σ minimumDuration(run)`.
    ///
    /// Never negative; an already-overrunning timeline reports `0`.
    public func maximumExtension(
        blocks: [TimeBlockModel],
        activeBlockID: UUID
    ) -> TimeInterval? {
        let sorted = blocks.sorted(by: Self.canonicalOrder)
        guard let activeIndex = sorted.firstIndex(where: { $0.id == activeBlockID }) else {
            return nil
        }

        var fluidRunStart: Date?
        var runMinimumsTotal: TimeInterval = 0
        var wall: TimeBlockModel?
        if activeIndex + 1 < sorted.count {
            for i in (activeIndex + 1)..<sorted.count {
                let block = sorted[i]
                if block.isPinned {
                    wall = block
                    break
                }
                if fluidRunStart == nil { fluidRunStart = block.scheduledStart }
                runMinimumsTotal += block.minimumDuration
            }
        }
        guard let wall else { return nil }

        if let fluidRunStart {
            return max(0, wall.scheduledStart.timeIntervalSince(fluidRunStart) - runMinimumsTotal)
        }
        let active = sorted[activeIndex]
        let activeEnd = active.scheduledStart.addingTimeInterval(active.duration)
        return max(0, wall.scheduledStart.timeIntervalSince(activeEnd))
    }

    /// Live-mode `+x`: the active block is already running, so the delta
    /// **extends its duration** — `scheduledStart` stays in the past where it
    /// belongs — and downstream blocks restructure around the new end:
    ///
    /// - Subsequent fluid blocks shift later by `delta`, up to the first
    ///   pinned block (the same bounded-ripple wall as ``recalculate``).
    /// - A fluid run trapped before the wall is compressed proportionally
    ///   (minimum durations respected) by the shared stage-3/4 pipeline.
    /// - If the wall cannot absorb the extension, the call returns
    ///   ``RippleStatus/exceedsAvailableSlack`` **without mutating anything**
    ///   — live mode has no "review later"; pair with ``maximumExtension``
    ///   to tell the user how far they *can* extend.
    ///
    /// A pinned **active** block may still extend: a pin anchors the start,
    /// not the duration. Non-positive deltas and unknown IDs are no-ops.
    public func applyExtension(
        blocks: [TimeBlockModel],
        activeBlockID: UUID,
        delta: TimeInterval,
        adjacency: [UUID: [UUID]]? = nil
    ) -> RippleResult {
        let sorted = blocks.sorted(by: Self.canonicalOrder)

        guard delta > 0,
              let activeIndex = sorted.firstIndex(where: { $0.id == activeBlockID }) else {
            return RippleResult(blocks: sorted, status: .clean)
        }

        // Atomic slack check BEFORE any mutation: reject outright when the
        // first downstream wall can't absorb the extension.
        if let maximum = maximumExtension(blocks: blocks, activeBlockID: activeBlockID),
           delta > maximum {
            return RippleResult(blocks: sorted, status: .exceedsAvailableSlack)
        }

        // Explicit dependents keep their cross-wall contract (see recalculate).
        let dependentIDs: Set<UUID>
        if let adjacency {
            switch dependencyResolver.resolve(adjacency: adjacency, from: activeBlockID) {
            case .success(let ids):
                dependentIDs = ids
            case .failure:
                return RippleResult(blocks: sorted, status: .circularDependency)
            }
        } else {
            dependentIDs = []
        }

        // Bounded ripple set: the fluid run between the active block and the
        // first pinned wall, in timeline order. The wall and run are captured
        // here because the squeeze below is driven by this known membership —
        // collision detection can't be trusted for it (a block pushed fully
        // past the wall sorts after it and escapes both the detector and the
        // backward trapped-run walk).
        var trappedRun: [TimeBlockModel] = []
        var wall: TimeBlockModel?
        if activeIndex + 1 < sorted.count {
            for i in (activeIndex + 1)..<sorted.count {
                if sorted[i].isPinned {
                    wall = sorted[i]
                    break
                }
                trappedRun.append(sorted[i])
            }
        }
        let shiftableIDs = Set(trappedRun.map(\.id)).union(dependentIDs)

        // Extend the active block in place; only its end moves.
        sorted[activeIndex].duration += delta

        for block in sorted
            where shiftableIDs.contains(block.id) && !block.isPinned && block.id != activeBlockID {
            block.scheduledStart = block.scheduledStart.addingTimeInterval(delta)
        }

        // Squeeze the run directly against the wall when it overruns. The
        // active block is never part of the run — it is running and its
        // just-extended duration is ground truth.
        var squeezeStatus: RippleStatus = .clean
        var squeezedIDs = Set<UUID>()
        if let wall, let lastRunBlock = trappedRun.last {
            let runEnd = lastRunBlock.scheduledStart.addingTimeInterval(lastRunBlock.duration)
            if runEnd > wall.scheduledStart {
                let startsBefore = Dictionary(uniqueKeysWithValues: trappedRun.map { ($0.id, $0.scheduledStart) })
                let durationsBefore = Dictionary(uniqueKeysWithValues: trappedRun.map { ($0.id, $0.duration) })

                let compression = compressionCalculator.compress(
                    run: trappedRun,
                    wallStart: wall.scheduledStart
                )
                squeezeStatus = compression.status == .impossible ? .impossible : .hasCollisions
                squeezedIDs = Set(
                    trappedRun.filter {
                        startsBefore[$0.id] != $0.scheduledStart || durationsBefore[$0.id] != $0.duration
                    }.map(\.id)
                )
            }
        }

        // General pass for everything else (explicit dependents crossing
        // walls, pre-existing overlaps); the barrier keeps the active block
        // out of any collision-driven trapped run.
        let resolved = resolveCollisions(blocks: blocks, barrierBlockID: activeBlockID)

        let status: RippleStatus
        if squeezeStatus == .impossible || resolved.status == .impossible {
            status = .impossible
        } else if squeezeStatus == .hasCollisions || resolved.status == .hasCollisions {
            status = .hasCollisions
        } else {
            status = resolved.status
        }

        return RippleResult(
            blocks: resolved.blocks,
            collisions: resolved.collisions,
            compressedBlockIDs: resolved.compressedBlockIDs.union(squeezedIDs),
            status: status
        )
    }

    // MARK: - Shared stages 3–4

    /// Collision detection + compression, shared by ``applyShift`` and
    /// ``applyExtension``. Snapshots before compressing so
    /// `compressedBlockIDs` reports exactly what resolution changed.
    /// `barrierBlockID` (live extensions: the active block) bounds every
    /// trapped-run walk so the running block is never compressed.
    private func resolveCollisions(
        blocks: [TimeBlockModel],
        barrierBlockID: UUID? = nil
    ) -> RippleResult {
        let sorted = blocks.sorted(by: Self.canonicalOrder)
        let collisions = collisionDetector.detect(sortedBlocks: sorted)
        guard !collisions.isEmpty else {
            return RippleResult(blocks: sorted, status: .clean)
        }

        let startsBefore = Dictionary(uniqueKeysWithValues: sorted.map { ($0.id, $0.scheduledStart) })
        let durationsBefore = Dictionary(uniqueKeysWithValues: sorted.map { ($0.id, $0.duration) })

        var status: RippleStatus = .hasCollisions
        for collision in collisions {
            let compressed = compressionCalculator.compress(
                sortedBlocks: sorted,
                collision: collision,
                barrierBlockID: barrierBlockID
            )
            if compressed.status == .impossible {
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
