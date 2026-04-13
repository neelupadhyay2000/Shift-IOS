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
    /// - Returns: A ``CompressionResult`` with the adjusted blocks and status.
    public func compress(blocks: [TimeBlockModel], collision: Collision) -> CompressionResult {
        let sorted = blocks.sorted { $0.scheduledStart < $1.scheduledStart }
        return compress(sortedBlocks: sorted, collision: collision)
    }

    /// Pre-sorted variant — avoids an O(n log n) sort on every call.
    ///
    /// Use this overload when the caller has already sorted the blocks array
    /// (e.g., inside a loop that processes multiple collisions from the same
    /// sorted snapshot).
    public func compress(sortedBlocks sorted: [TimeBlockModel], collision: Collision) -> CompressionResult {

        guard let pinnedIndex = sorted.firstIndex(where: { $0.id == collision.pinnedBlockID }) else {
            return CompressionResult(blocks: sorted, status: .clean)
        }

        // Walk backwards from the pinned block to find consecutive trapped Fluid blocks.
        var trappedStartIndex = pinnedIndex
        while trappedStartIndex > 0 && !sorted[trappedStartIndex - 1].isPinned {
            trappedStartIndex -= 1
        }

        let trappedRange = trappedStartIndex..<pinnedIndex
        guard !trappedRange.isEmpty else {
            return CompressionResult(blocks: sorted, status: .clean)
        }

        let gapStart = sorted[trappedRange.lowerBound].scheduledStart
        let availableTime = sorted[pinnedIndex].scheduledStart.timeIntervalSince(gapStart)

        // No feasible gap — mark impossible.
        guard availableTime > 0 else {
            for index in trappedRange {
                let block = sorted[index]
                block.duration = block.minimumDuration
                block.requiresReview = true
            }
            return CompressionResult(blocks: sorted, status: .impossible)
        }

        let totalDuration = sorted[trappedRange].reduce(0.0) { $0 + $1.duration }
        guard totalDuration > 0 else {
            return CompressionResult(blocks: sorted, status: .clean)
        }

        let totalMinimum = sorted[trappedRange].reduce(0.0) { $0 + $1.minimumDuration }

        // Impossible: minimums exceed available gap.
        if totalMinimum > availableTime {
            var cursor = gapStart
            for index in trappedRange {
                let block = sorted[index]
                block.scheduledStart = cursor
                block.duration = block.minimumDuration
                block.requiresReview = true
                cursor = cursor.addingTimeInterval(block.minimumDuration)
            }
            return CompressionResult(blocks: sorted, status: .impossible)
        }

        // If blocks already fit, just close gaps — don't expand durations.
        if totalDuration <= availableTime {
            var cursor = gapStart
            for index in trappedRange {
                let block = sorted[index]
                block.scheduledStart = cursor
                cursor = cursor.addingTimeInterval(block.duration)
            }
            return CompressionResult(blocks: sorted, status: .clean)
        }

        // Proportional compression with minimum-duration protection.
        var newDurations = [TimeInterval](repeating: 0, count: trappedRange.count)

        // Pass 1: proportional scaling.
        for (i, index) in trappedRange.enumerated() {
            newDurations[i] = (sorted[index].duration / totalDuration) * availableTime
        }

        // Pass 2: clamp to minimumDuration, redistribute deficit using
        // excess-over-minimum for more stable convergence.
        var changed = true
        while changed {
            changed = false
            var deficit: TimeInterval = 0
            var totalExcess: TimeInterval = 0

            // Identify blocks below minimum and compute total excess of flexible blocks.
            for (i, index) in trappedRange.enumerated() {
                let minDur = sorted[index].minimumDuration
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
                for (i, index) in trappedRange.enumerated() {
                    let minDur = sorted[index].minimumDuration
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
        for (i, index) in trappedRange.enumerated() {
            let block = sorted[index]
            block.scheduledStart = cursor
            block.duration = newDurations[i]
            cursor = cursor.addingTimeInterval(newDurations[i])
        }

        return CompressionResult(blocks: sorted, status: .clean)
    }
}
