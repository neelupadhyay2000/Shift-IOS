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

        // Proportionally compress durations and lay out contiguously.
        var cursor = gapStart
        for index in trappedRange {
            let block = sorted[index]
            let newDuration = (block.duration / totalDuration) * availableTime
            block.scheduledStart = cursor
            block.duration = newDuration
            cursor = cursor.addingTimeInterval(newDuration)
        }

        return sorted
    }
}
