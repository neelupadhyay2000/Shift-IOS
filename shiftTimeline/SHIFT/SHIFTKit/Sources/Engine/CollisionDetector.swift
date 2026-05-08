import Foundation
import Models

// MARK: - CollisionDetector

/// Scans time blocks for temporal overlaps between Fluid and Pinned blocks. Stage 3 of the Ripple Engine pipeline.
public struct CollisionDetector: Sendable {

    public init() {}

    /// Detects collisions between Fluid and Pinned blocks.
    /// Mutates `requiresReview` on every Fluid block as a side effect — colliding blocks get `true`, others `false`.
    public func detect(blocks: [TimeBlockModel]) -> [Collision] {
        let sorted = blocks.sorted {
            if $0.scheduledStart != $1.scheduledStart {
                return $0.scheduledStart < $1.scheduledStart
            }
            return !$0.isPinned && $1.isPinned
        }
        return detect(sortedBlocks: sorted)
    }

    /// Pre-sorted variant — skips the O(n log n) sort.
    public func detect(sortedBlocks sorted: [TimeBlockModel]) -> [Collision] {
        var collisions: [Collision] = []
        var collidingFluidIDs = Set<UUID>()

        for (index, block) in sorted.enumerated() where !block.isPinned {
            let fluidEnd = block.scheduledStart.addingTimeInterval(block.duration)

            for pinned in sorted[(index + 1)...] {
                // Early exit: sorted by start, so nothing further can overlap.
                guard pinned.scheduledStart < fluidEnd else { break }
                guard pinned.isPinned else { continue }

                let overlapSeconds = fluidEnd.timeIntervalSince(pinned.scheduledStart)
                let overlapMinutes = Int(overlapSeconds / 60)
                collisions.append(
                    Collision(
                        fluidBlockID: block.id,
                        pinnedBlockID: pinned.id,
                        overlapMinutes: overlapMinutes
                    )
                )
                collidingFluidIDs.insert(block.id)
            }
        }

        // Stamp requiresReview on every Fluid block so stale flags are cleared.
        for block in sorted where !block.isPinned {
            block.requiresReview = collidingFluidIDs.contains(block.id)
        }

        return collisions
    }
}
