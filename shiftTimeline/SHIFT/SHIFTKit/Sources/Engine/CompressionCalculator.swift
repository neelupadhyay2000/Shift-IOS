import Foundation
import Models

/// The outcome of a compression pass.
public struct CompressionResult {
    public let blocks: [TimeBlockModel]
    public let status: RippleStatus

    public init(blocks: [TimeBlockModel], status: RippleStatus) {
        self.blocks = blocks
        self.status = status
    }
}

/// Calculates how blocks can be compressed toward their minimum duration
/// to resolve collisions with Pinned blocks.
public struct CompressionCalculator: Sendable {
    public init() {}

    /// Proportionally compresses trapped Fluid blocks so they fit within the
    /// available gap before a Pinned block.
    ///
    /// "Trapped" blocks are the consecutive run of Fluid blocks immediately
    /// preceding the Pinned block identified by the collision.
    ///
    /// **Behaviour by case:**
    /// - `totalDuration <= availableTime`: blocks are laid out contiguously
    ///   (closing gaps) but durations are **not** expanded. Status: `.clean`.
    /// - `totalDuration > availableTime` and minimums fit: each block's
    ///   duration is scaled by `(block.duration / totalDuration) * availableTime`,
    ///   clamped to `minimumDuration`. Status: `.clean`.
    /// - `sum(minimumDurations) > availableTime`: all trapped blocks are set
    ///   to `minimumDuration`, flagged `requiresReview = true`. Status: `.impossible`.
    /// - `availableTime <= 0`: no feasible compression exists. Trapped blocks
    ///   are set to `minimumDuration`, flagged `requiresReview = true`.
    ///   Status: `.impossible`.
    ///
    /// ## Mutation Semantics
    ///
    /// `TimeBlockModel` is a reference-type SwiftData `@Model`. This method
    /// **mutates `scheduledStart`, `duration`, and potentially `requiresReview`
    /// directly on the passed-in instances** so that SwiftData's change-tracking
    /// picks up the modifications automatically. The ``CompressionResult/blocks``
    /// array holds references to the same (now-mutated) objects — it is **not**
    /// a set of independent copies.
    ///
    /// Callers that need undo/redo support should **snapshot** the relevant
    /// properties *before* calling this method.
    ///
    /// - Parameters:
    ///   - blocks: All time blocks in the timeline (sorted or unsorted).
    ///   - collision: The collision that triggered compression.
    ///   - barrierBlockID: Optional lower bound for the trapped-run walk
    ///     (see the pre-sorted variant).
    /// - Returns: A ``CompressionResult`` with the adjusted blocks and status.
    public func compress(
        blocks: [TimeBlockModel],
        collision: Collision,
        barrierBlockID: UUID? = nil
    ) -> CompressionResult {
        let sorted = blocks.sorted { $0.scheduledStart < $1.scheduledStart }
        return compress(sortedBlocks: sorted, collision: collision, barrierBlockID: barrierBlockID)
    }

    /// Pre-sorted variant — avoids an O(n log n) sort on every call.
    ///
    /// Use this overload when the caller has already sorted the blocks array
    /// (e.g., inside a loop that processes multiple collisions from the same
    /// sorted snapshot).
    ///
    /// `barrierBlockID` bounds the backward trapped-run walk: the walk stops
    /// *before* that block, so it is never compressed. Live extensions pass
    /// the active block here — it is already running, and its just-extended
    /// duration is ground truth that compression must not shrink. `nil`
    /// (planning-mode shifts) keeps the historic behaviour where the run
    /// extends back to the previous pinned block.
    public func compress(
        sortedBlocks sorted: [TimeBlockModel],
        collision: Collision,
        barrierBlockID: UUID? = nil
    ) -> CompressionResult {

        guard let pinnedIndex = sorted.firstIndex(where: { $0.id == collision.pinnedBlockID }) else {
            return CompressionResult(blocks: sorted, status: .clean)
        }

        // Walk backwards from the pinned block to find consecutive trapped
        // Fluid blocks, stopping at a pinned block or the barrier.
        var trappedStartIndex = pinnedIndex
        while trappedStartIndex > 0,
              !sorted[trappedStartIndex - 1].isPinned,
              sorted[trappedStartIndex - 1].id != barrierBlockID {
            trappedStartIndex -= 1
        }

        let trappedRange = trappedStartIndex..<pinnedIndex
        guard !trappedRange.isEmpty else {
            return CompressionResult(blocks: sorted, status: .clean)
        }

        let status = compress(
            trapped: Array(sorted[trappedRange]),
            beforeWallAt: sorted[pinnedIndex].scheduledStart
        )
        return CompressionResult(blocks: sorted, status: status)
    }

    /// Run-explicit variant for live extensions (``RippleEngine/applyExtension``).
    ///
    /// The collision-driven variants discover the trapped run by walking the
    /// post-shift sort order backwards from the pinned block — but a block
    /// pushed *fully past* the wall sorts after it and escapes both the walk
    /// and collision detection entirely. The extension pipeline already knows
    /// the run a priori (the fluid blocks between the active block and the
    /// wall, in timeline order), so it passes the membership explicitly.
    ///
    /// Same case behaviour and mutation semantics as the collision-driven
    /// variants; `run` must be in timeline order.
    public func compress(run: [TimeBlockModel], wallStart: Date) -> CompressionResult {
        CompressionResult(blocks: run, status: compress(trapped: run, beforeWallAt: wallStart))
    }

    // MARK: - Shared core

    /// Lays out `trapped` (timeline order) to fit before `wallStart`,
    /// compressing proportionally toward minimum durations when needed.
    private func compress(trapped: [TimeBlockModel], beforeWallAt wallStart: Date) -> RippleStatus {
        guard let firstBlock = trapped.first else { return .clean }

        let gapStart = firstBlock.scheduledStart
        let availableTime = wallStart.timeIntervalSince(gapStart)

        // No feasible gap — mark impossible.
        guard availableTime > 0 else {
            for block in trapped {
                block.duration = block.minimumDuration
                block.requiresReview = true
            }
            return .impossible
        }

        let totalDuration = trapped.reduce(0.0) { $0 + $1.duration }
        guard totalDuration > 0 else { return .clean }

        let totalMinimum = trapped.reduce(0.0) { $0 + $1.minimumDuration }

        // Impossible: minimums exceed available gap.
        if totalMinimum > availableTime {
            var cursor = gapStart
            for block in trapped {
                block.scheduledStart = cursor
                block.duration = block.minimumDuration
                block.requiresReview = true
                cursor = cursor.addingTimeInterval(block.minimumDuration)
            }
            return .impossible
        }

        // If blocks already fit, just close gaps — don't expand durations.
        if totalDuration <= availableTime {
            var cursor = gapStart
            for block in trapped {
                block.scheduledStart = cursor
                cursor = cursor.addingTimeInterval(block.duration)
            }
            return .clean
        }

        // Proportional compression with minimum-duration protection.
        //
        // Pass 1: proportional scaling.
        var newDurations = trapped.map { ($0.duration / totalDuration) * availableTime }

        // Pass 2: clamp to minimumDuration, redistribute deficit using
        // excess-over-minimum for more stable convergence.
        var changed = true
        while changed {
            changed = false
            var deficit: TimeInterval = 0
            var totalExcess: TimeInterval = 0

            // Identify blocks below minimum and compute total excess of flexible blocks.
            for (i, block) in trapped.enumerated() {
                let minDur = block.minimumDuration
                if newDurations[i] < minDur {
                    deficit += minDur - newDurations[i]
                    newDurations[i] = minDur
                    changed = true
                } else {
                    totalExcess += newDurations[i] - minDur
                }
            }

            // Redistribute deficit proportionally by each block's excess over minimum.
            if changed && totalExcess > 0 {
                for (i, block) in trapped.enumerated() {
                    let minDur = block.minimumDuration
                    let excess = newDurations[i] - minDur
                    if excess > 0 {
                        let share = (excess / totalExcess) * deficit
                        newDurations[i] -= share
                    }
                }
            }
        }

        // Lay out contiguously.
        var cursor = gapStart
        for (i, block) in trapped.enumerated() {
            block.scheduledStart = cursor
            block.duration = newDurations[i]
            cursor = cursor.addingTimeInterval(newDurations[i])
        }

        return .clean
    }
}
