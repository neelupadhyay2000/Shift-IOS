import Foundation
import Models

// MARK: - TimelinePacker

/// Re-packs a timeline's fluid blocks contiguously, treating pinned blocks as
/// fixed anchors — the scheduling math behind a manual reorder and a delete.
///
/// Pure and stateless (the same shape as ``RippleEngine``): it **mutates the
/// passed-in `TimeBlockModel` instances in place** so SwiftData's change-tracking
/// picks the edits up automatically. It performs no I/O and no persistence — the
/// caller owns snapshotting (for undo) and saving.
///
/// This is intentionally separate from ``RippleEngine``: the ripple engine
/// propagates a *delta* outward from one changed block (bounded by pinned walls),
/// whereas the packer *re-lays the whole sequence* from a known origin. Both keep
/// the timeline math out of the UI layer and unit-testable.
public struct TimelinePacker: Sendable {
    public init() {}

    /// Walks `blocks` **in the given order**, packing each *fluid* block to start
    /// at a running cursor and advancing the cursor by that block's duration.
    /// *Pinned* blocks keep their fixed clock time and push the cursor forward to
    /// their end when they sit later than it, so the fluid run resumes after the
    /// anchor instead of overlapping it.
    ///
    /// - Parameters:
    ///   - blocks: the blocks to pack, in the desired visual / timeline order.
    ///   - origin: the start time for a leading fluid run. Ignored when the first
    ///     block is pinned — its own start anchors the walk. (Because a pinned
    ///     block's end is `≥` any earlier origin, passing the run's minimum start
    ///     here reproduces an unconditional `cursor = origin` start exactly.)
    ///   - syncOriginalStart: when `true`, also set each repacked fluid block's
    ///     `originalStart` to its new start, so the ripple engine's backward-shift
    ///     clamp reflects the block's new slot rather than its old one. Used by the
    ///     delete path.
    ///   - clearRequiresReview: when `true`, clear each repacked fluid block's
    ///     `requiresReview` flag — a structural repack resolves stale collision
    ///     flags. Used by the delete path.
    public func pack(
        _ blocks: [TimeBlockModel],
        origin: Date,
        syncOriginalStart: Bool = false,
        clearRequiresReview: Bool = false
    ) {
        guard let first = blocks.first else { return }
        var cursor = first.isPinned ? first.scheduledStart : origin
        for block in blocks {
            if block.isPinned {
                cursor = max(cursor, block.scheduledStart.addingTimeInterval(block.duration))
            } else {
                block.scheduledStart = cursor
                if syncOriginalStart { block.originalStart = cursor }
                if clearRequiresReview { block.requiresReview = false }
                cursor = cursor.addingTimeInterval(block.duration)
            }
        }
    }
}
