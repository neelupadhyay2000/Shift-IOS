import Foundation
import Models

// MARK: - PreviewBlock

/// Value-type mirror of mutable ``TimeBlockModel`` fields. Engine stages operate on these copies so live objects are never mutated during preview generation.
public struct PreviewBlock: Sendable, Equatable {
    public let id: UUID
    public let title: String
    public var scheduledStart: Date
    public let originalStart: Date
    public var duration: TimeInterval
    public let minimumDuration: TimeInterval
    public let isPinned: Bool
    public var requiresReview: Bool
    public let status: BlockStatus

    public init(
        id: UUID,
        title: String,
        scheduledStart: Date,
        originalStart: Date,
        duration: TimeInterval,
        minimumDuration: TimeInterval,
        isPinned: Bool,
        requiresReview: Bool,
        status: BlockStatus
    ) {
        self.id = id
        self.title = title
        self.scheduledStart = scheduledStart
        self.originalStart = originalStart
        self.duration = duration
        self.minimumDuration = minimumDuration
        self.isPinned = isPinned
        self.requiresReview = requiresReview
        self.status = status
    }
}

// MARK: - PreviewBlock + TimeBlockModel

public extension PreviewBlock {
    /// Creates a `PreviewBlock` by copying current field values from a live ``TimeBlockModel``.
    init(copying block: TimeBlockModel) {
        self.init(
            id: block.id,
            title: block.title,
            scheduledStart: block.scheduledStart,
            originalStart: block.originalStart,
            duration: block.duration,
            minimumDuration: block.minimumDuration,
            isPinned: block.isPinned,
            requiresReview: block.requiresReview,
            status: block.status
        )
    }
}

// MARK: - ShiftPreview

/// Non-mutating result of a preview recalculation. Use `diffs` to drive visual indicators.
public struct ShiftPreview: Sendable {
    /// Projected state of every block after the proposed shift, sorted by `scheduledStart`.
    public let previewBlocks: [PreviewBlock]

    /// Collisions detected in the projected timeline.
    public let collisions: [Collision]

    /// IDs of blocks whose duration was compressed to resolve a collision.
    public let compressedBlockIDs: Set<UUID>

    /// Overall status of the projected timeline.
    public let status: RippleStatus

    /// Per-block start-time delta vs. the original `scheduledStart` at call time.
    /// Every input block has an entry; blocks that don't move receive `0`.
    public let diffs: [UUID: TimeInterval]

    public init(
        previewBlocks: [PreviewBlock],
        collisions: [Collision],
        compressedBlockIDs: Set<UUID>,
        status: RippleStatus,
        diffs: [UUID: TimeInterval]
    ) {
        self.previewBlocks = previewBlocks.sorted { $0.scheduledStart < $1.scheduledStart }
        self.collisions = collisions
        self.compressedBlockIDs = compressedBlockIDs
        self.status = status
        self.diffs = diffs
    }
}

// MARK: - ShiftPreviewGenerator

/// Produces a ``ShiftPreview`` for a proposed shift without mutating any live `TimeBlockModel` instances.
public struct ShiftPreviewGenerator: Sendable {

    private let dependencyResolver: DependencyResolver
    private let collisionDetector: CollisionDetector
    private let compressionCalculator: CompressionCalculator

    public init(
        dependencyResolver: DependencyResolver = .init(),
        collisionDetector: CollisionDetector = .init(),
        compressionCalculator: CompressionCalculator = .init()
    ) {
        self.dependencyResolver = dependencyResolver
        self.collisionDetector = collisionDetector
        self.compressionCalculator = compressionCalculator
    }

    /// Generates a projected timeline for a proposed shift without mutating any live block references.
    /// Early-exit paths return a preview with all `diffs` set to `0` — never an empty dictionary.
    public func generatePreview(
        blocks: [TimeBlockModel],
        blockID: UUID,
        delta: TimeInterval
    ) -> ShiftPreview {
        // Capture original start times before any work so diffs are accurate.
        let originalStarts = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0.scheduledStart) })

        // Copy every live block into a value-type PreviewBlock, sorted once.
        var preview = blocks.map { PreviewBlock(copying: $0) }
        preview.sort { $0.scheduledStart < $1.scheduledStart }

        // Zero diffs: every block present with value 0 (nothing moved).
        let zeroDiffs = Dictionary(uniqueKeysWithValues: preview.map { ($0.id, TimeInterval(0)) })

        guard delta != 0,
              let changedIndex = preview.firstIndex(where: { $0.id == blockID }) else {
            return ShiftPreview(
                previewBlocks: preview,
                collisions: [],
                compressedBlockIDs: [],
                status: .clean,
                diffs: zeroDiffs
            )
        }

        guard !preview[changedIndex].isPinned else {
            return ShiftPreview(
                previewBlocks: preview,
                collisions: [],
                compressedBlockIDs: [],
                status: .pinnedBlockCannotShift,
                diffs: zeroDiffs
            )
        }

        // --- Stage 1: Shift Set Calculation ---
        //
        // generatePreview uses temporal ordering only — no explicit caller-supplied
        // adjacency. Building a 200-node adjacency dict and running BFS from
        // blockID is redundant: the BFS result equals subsequentFluidIDs (after
        // filtering pinned blocks in Stage 2). Skip it entirely.
        //
        // The bounded-ripple rule still applies: all fluid blocks after the
        // changed block are shiftable regardless of whether a pinned block sits
        // between them and the changed block (the preview intentionally shows
        // the unconstrained projection so the user sees the full collision zone).
        let shiftableIDs = Set(
            preview[(changedIndex + 1)...].filter { !$0.isPinned }.map(\.id)
        )

        // --- Stage 2: Shift Propagation (on value copies) ---
        if delta > 0 {
            preview[changedIndex].scheduledStart =
                preview[changedIndex].scheduledStart.addingTimeInterval(delta)
        } else {
            preview[changedIndex].scheduledStart = max(
                preview[changedIndex].originalStart,
                preview[changedIndex].scheduledStart.addingTimeInterval(delta)
            )
        }

        for i in 0..<preview.count where shiftableIDs.contains(preview[i].id) && !preview[i].isPinned {
            if delta > 0 {
                preview[i].scheduledStart = preview[i].scheduledStart.addingTimeInterval(delta)
            } else {
                preview[i].scheduledStart = max(
                    preview[i].originalStart,
                    preview[i].scheduledStart.addingTimeInterval(delta)
                )
            }
        }

        // --- Stage 3 & 4: Collision Detection + Compression ---
        // Wrap preview blocks in temporary TimeBlockModel instances so the
        // existing CollisionDetector and CompressionCalculator can operate on
        // them without modification.
        var tempBlocks = preview.map { pb -> TimeBlockModel in
            TimeBlockModel(
                id: pb.id,
                title: pb.title,
                scheduledStart: pb.scheduledStart,
                originalStart: pb.originalStart,
                duration: pb.duration,
                minimumDuration: pb.minimumDuration,
                isPinned: pb.isPinned,
                requiresReview: pb.requiresReview
            )
        }

        // Sort once — reuse for detect and all compress calls.
        tempBlocks.sort {
            if $0.scheduledStart != $1.scheduledStart {
                return $0.scheduledStart < $1.scheduledStart
            }
            return !$0.isPinned && $1.isPinned
        }

        let collisions = collisionDetector.detect(sortedBlocks: tempBlocks)

        var compressedIDs = Set<UUID>()
        var finalStatus: RippleStatus = collisions.isEmpty ? .clean : .hasCollisions

        for collision in collisions {
            let result = compressionCalculator.compress(sortedBlocks: tempBlocks, collision: collision)
            compressedIDs.formUnion(
                result.blocks.filter { $0.id != collision.pinnedBlockID }.map(\.id)
            )
            if result.status == .impossible {
                finalStatus = .impossible
            }
        }

        // Copy the (possibly compressed) temp block state back into PreviewBlocks
        // using index-aligned arrays (both are sorted by scheduledStart).
        let tempByID = Dictionary(tempBlocks.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        var finalPreview = preview.map { pb -> PreviewBlock in
            guard let temp = tempByID[pb.id] else { return pb }
            var updated = pb
            updated.scheduledStart = temp.scheduledStart
            updated.duration = temp.duration
            updated.requiresReview = temp.requiresReview
            return updated
        }
        finalPreview.sort { $0.scheduledStart < $1.scheduledStart }

        // --- Diffs: every block gets an entry; value = previewStart − originalStart.
        let diffs = Dictionary(uniqueKeysWithValues: finalPreview.compactMap { pb -> (UUID, TimeInterval)? in
            guard let original = originalStarts[pb.id] else { return nil }
            return (pb.id, pb.scheduledStart.timeIntervalSince(original))
        })

        return ShiftPreview(
            previewBlocks: finalPreview,
            collisions: collisions,
            compressedBlockIDs: compressedIDs,
            status: finalStatus,
            diffs: diffs
        )
    }
}
