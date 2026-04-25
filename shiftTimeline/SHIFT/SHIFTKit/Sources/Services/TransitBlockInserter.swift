import Foundation
import Models
import SwiftData

/// Side-effecting service that inserts an auto-generated transit block between
/// two consecutive venue-switching blocks.
///
/// Lives in `Services` (not `Engine`) because it mutates SwiftData `@Model`
/// references and inserts into a `ModelContext`. Pure scheduling math could be
/// lifted into `Engine` later if a non-SwiftData call site appears.
@MainActor
public enum TransitBlockInserter {

    /// Inserts a Fluid transit block immediately after `originBlock`.
    ///
    /// Preserves `destinationBlock.scheduledStart` (and every subsequent block's
    /// timing) by:
    ///  1. consuming any existing gap between origin and destination,
    ///  2. shrinking origin's duration down to `minimumDuration`,
    ///  3. only as a last resort, shifting destination + downstream non-pinned
    ///     blocks forward by the remaining shortfall.
    ///
    /// - Parameters:
    ///   - minutes: Travel time in minutes (must be > 0).
    ///   - originBlock: Block the user is leaving.
    ///   - destinationBlock: Block the user is arriving at.
    ///   - allBlocks: All blocks in the current timeline (used for downstream shift).
    ///   - defaultTrack: Fallback track when the origin has none assigned.
    ///   - context: The active `ModelContext` to insert into.
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

        // 1. Consume any existing gap between origin and destination first.
        let neededFromOrigin = max(0, transitDuration - gap)

        // 2. Pull from origin's duration, respecting its minimum duration.
        let originSlack = max(0, originBlock.duration - originBlock.minimumDuration)
        let pulledFromOrigin = min(neededFromOrigin, originSlack)
        if pulledFromOrigin > 0 {
            originBlock.duration -= pulledFromOrigin
        }

        // 3. If origin couldn't absorb everything, shift destination + subsequent
        //    non-pinned blocks forward by the remainder.
        let stillNeeded = neededFromOrigin - pulledFromOrigin
        if stillNeeded > 0 {
            for block in allBlocks
                where block.scheduledStart >= destinationBlock.scheduledStart && !block.isPinned {
                block.scheduledStart = block.scheduledStart.addingTimeInterval(stillNeeded)
            }
        }

        // Transit slots in starting at the (possibly shortened) origin's new end.
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
