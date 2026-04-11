import Foundation
import Models

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
    /// - Parameters:
    ///   - blocks: All time blocks in the timeline (sorted or unsorted).
    ///   - collision: The collision that triggered compression.
    /// - Returns: The full block array with trapped blocks compressed in place.
    public func compress(blocks: [TimeBlockModel], collision: Collision) -> [TimeBlockModel] {
        let sorted = blocks.sorted { $0.scheduledStart < $1.scheduledStart }

        guard let pinnedIndex = sorted.firstIndex(where: { $0.id == collision.pinnedBlockID }) else {
            return sorted
        }

        // Walk backwards from the pinned block to find consecutive trapped Fluid blocks.
        var trappedStartIndex = pinnedIndex
        while trappedStartIndex > 0 && !sorted[trappedStartIndex - 1].isPinned {
            trappedStartIndex -= 1
        }

        let trappedRange = trappedStartIndex..<pinnedIndex
        guard !trappedRange.isEmpty else { return sorted }

        let trappedBlocks = sorted[trappedRange]
        let gapStart = trappedBlocks.first!.scheduledStart
        let availableTime = sorted[pinnedIndex].scheduledStart.timeIntervalSince(gapStart)

        guard availableTime > 0 else { return sorted }

        let totalDuration = trappedBlocks.reduce(0.0) { $0 + $1.duration }
        guard totalDuration > 0 else { return sorted }

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

            // Find blocks that fall below minimum and accumulate deficit.
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

            // Redistribute deficit proportionally among flexible blocks.
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

        return sorted
    }
}
