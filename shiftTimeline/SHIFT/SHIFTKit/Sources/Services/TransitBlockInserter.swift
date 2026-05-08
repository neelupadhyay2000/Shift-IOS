import Foundation
import Models
import SwiftData

/// Inserts an auto-generated transit block between two consecutive venue-switching blocks.
@MainActor
public enum TransitBlockInserter {

    /// Inserts a Fluid transit block after `originBlock`, preserving downstream timing.
    /// Consumes gap, then shrinks origin, then shifts downstream as last resort.
    public static func insert(
        minutes: Int,
        after originBlock: TimeBlockModel,
        before destinationBlock: TimeBlockModel,
        allBlocks: [TimeBlockModel],
        defaultTrack: TimelineTrack?,
        context: ModelContext
    ) {
        let destinationName = destinationBlock.venueName.isEmpty
            ? destinationBlock.title
            : destinationBlock.venueName

        let transitDuration = TimeInterval(minutes * 60)
        let originEnd = originBlock.scheduledStart.addingTimeInterval(originBlock.duration)
        let gap = destinationBlock.scheduledStart.timeIntervalSince(originEnd)

        // 1. Consume gap. 2. Pull from origin. 3. Shift downstream if still needed.
        let neededFromOrigin = max(0, transitDuration - gap)

        // 2. Shrink origin.
        let originSlack = max(0, originBlock.duration - originBlock.minimumDuration)
        let pulledFromOrigin = min(neededFromOrigin, originSlack)
        if pulledFromOrigin > 0 {
            originBlock.duration -= pulledFromOrigin
        }

        // 3. Shift downstream non-pinned blocks if shortfall remains.
        let stillNeeded = neededFromOrigin - pulledFromOrigin
        if stillNeeded > 0 {
            for block in allBlocks
                where block.scheduledStart >= destinationBlock.scheduledStart && !block.isPinned {
                block.scheduledStart = block.scheduledStart.addingTimeInterval(stillNeeded)
            }
        }

        let transitStart = originBlock.scheduledStart.addingTimeInterval(originBlock.duration)

        let transit = TimeBlockModel(
            title: "Transit to \(destinationName)",
            scheduledStart: transitStart,
            duration: transitDuration,
            isPinned: false,
            colorTag: "#8E8E93",
            icon: "car.fill"
        )
        transit.isTransitBlock = true
        transit.track = originBlock.track ?? defaultTrack
        context.insert(transit)
    }
}
