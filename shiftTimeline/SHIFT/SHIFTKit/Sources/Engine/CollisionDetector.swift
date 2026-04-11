import Foundation
import Models

// MARK: - CollisionDetector

/// Scans a set of time blocks for temporal overlaps between Fluid and Pinned blocks.
///
/// This is Stage 3 of the Ripple Engine pipeline. It is a pure, stateless struct
/// with no side effects and no SwiftData imports.
public struct CollisionDetector: Sendable {

    public init() {}

    /// Detects collisions between Fluid and Pinned blocks.
    ///
    /// A collision occurs when a Fluid block's end time
    /// `(scheduledStart + duration)` exceeds the `scheduledStart` of any
    /// subsequent Pinned block. Only strict overlaps are reported — a Fluid
    /// block that ends exactly at a Pinned block's start is **not** a
    /// collision.
    ///
    /// ## Side Effects
    /// As part of detection this method mutates `requiresReview` on every
    /// Fluid block in `blocks`:
    /// - **Colliding** Fluid blocks → `requiresReview = true`
    /// - **Non-colliding** Fluid blocks → `requiresReview = false`
    ///
    /// This keeps `requiresReview` in sync with the current collision zone on
    /// every recalculation pass so stale flags are always cleared.
    ///
    /// - Parameter blocks: All time blocks in the current timeline.
    /// - Returns: One ``Collision`` per (Fluid, Pinned) overlapping pair,
    ///   sorted in the order the Fluid blocks appear in the timeline.
    public func detect(blocks: [TimeBlockModel]) -> [Collision] {
        // Primary sort: scheduledStart ascending.
        // Tie-breaker: Fluid (isPinned == false) before Pinned for equal start
        // times, so a Pinned block that shares a start with a Fluid block is
        // always visited after it and is never skipped by the inner loop.
        let sorted = blocks.sorted {
            if $0.scheduledStart != $1.scheduledStart {
                return $0.scheduledStart < $1.scheduledStart
            }
            return !$0.isPinned && $1.isPinned  // Fluid before Pinned on tie
        }
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
