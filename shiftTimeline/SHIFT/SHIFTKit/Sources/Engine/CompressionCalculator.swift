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
    /// preceding the Pinned block identified by the collision. Each block's
    /// duration is scaled by `(block.duration / totalDuration) * availableTime`,
    /// and `scheduledStart` values are laid out contiguously with no gaps.
    ///
    /// If `sum(minimumDurations) > availableTime`, all trapped blocks are set
    /// to their `minimumDuration`, flagged with `requiresReview = true`, and
    /// the result status is `.impossible`.
    ///
    /// - Parameters:
    ///   - blocks: All time blocks in the timeline (sorted or unsorted).
    ///   - collision: The collision that triggered compression.
    /// - Returns: A ``CompressionResult`` with the adjusted blocks and status.
    public func compress(blocks: [TimeBlockModel], collision: Collision) -> CompressionResult {
        let sorted = blocks.sorted { $0.scheduledStart < $1.scheduledStart }

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

        let trappedBlocks = sorted[trappedRange]
        let gapStart = trappedBlocks.first!.scheduledStart
        let availableTime = sorted[pinnedIndex].scheduledStart.timeIntervalSince(gapStart)

        guard availableTime > 0 else {
            return CompressionResult(blocks: sorted, status: .clean)
        }

        let totalDuration = trappedBlocks.reduce(0.0) { $0 + $1.duration }
        guard totalDuration > 0 else {
            return CompressionResult(blocks: sorted, status: .clean)
        }

        let totalMinimum = trappedBlocks.reduce(0.0) { $0 + $1.minimumDuration }

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

        // Two-pass compression: first proportional, then enforce minimums
        // and redistribute remaining time.
        var newDurations = [TimeInterval](repeating: 0, count: trappedRange.count)

        // Pass 1: proportional compression.
        for (i, index) in trappedRange.enumerated() {
            newDurations[i] = (sorted[index].duration / totalDuration) * availableTime
        }

        // Pass 2: clamp to minimumDuration, redistribute deficit.
        var changed = true
        while changed {
            changed = false
            var deficit: TimeInterval = 0
            var flexibleDuration: TimeInterval = 0

            for (i, index) in trappedRange.enumerated() {
                let minDur = sorted[index].minimumDuration
                if newDurations[i] < minDur {
                    deficit += minDur - newDurations[i]
                    newDurations[i] = minDur
                    changed = true
                } else if newDurations[i] > sorted[index].minimumDuration {
                    flexibleDuration += newDurations[i]
                }
            }

            if changed && flexibleDuration > 0 {
                for (i, index) in trappedRange.enumerated() {
                    let minDur = sorted[index].minimumDuration
                    if newDurations[i] > minDur {
                        let share = (newDurations[i] / flexibleDuration) * deficit
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

        return CompressionResult(blocks: sorted, status: .hasCollisions)
    }
}
