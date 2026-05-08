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

    /// Proportionally compresses trapped Fluid blocks to fit within the available gap before a Pinned block.
    /// Mutates `scheduledStart`, `duration`, and `requiresReview` on passed-in instances directly.
    public func compress(blocks: [TimeBlockModel], collision: Collision) -> CompressionResult {
        let sorted = blocks.sorted { $0.scheduledStart < $1.scheduledStart }
        return compress(sortedBlocks: sorted, collision: collision)
    }

    /// Pre-sorted variant — skips the O(n log n) sort.
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
