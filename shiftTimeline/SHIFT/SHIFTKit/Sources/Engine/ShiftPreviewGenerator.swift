import Foundation
import Models

// MARK: - PreviewBlock

/// A value-type mirror of the fields on ``TimeBlockModel`` that the ripple
/// pipeline reads and writes.
///
/// `ShiftPreviewGenerator` copies each live `TimeBlockModel` into a
/// `PreviewBlock` before running the engine stages, so the originals are
/// **never mutated** during preview generation. The preview result is expressed
/// entirely in terms of `PreviewBlock` values.
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
    /// Creates a `PreviewBlock` by copying the current field values off a
    /// live ``TimeBlockModel`` reference.
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

/// The non-mutating result of a preview recalculation.
///
/// Contains the projected state of every block **after** the proposed shift,
/// without having modified any live `TimeBlockModel` instances. Use `diffs`
/// to drive visual indicators (e.g. highlighting which blocks would move and
/// by how much).
public struct ShiftPreview: Sendable {
    /// The projected state of every block after the proposed shift, sorted by
    /// `scheduledStart` ascending. These are value-type copies — the live
    /// SwiftData objects are untouched.
    public let previewBlocks: [PreviewBlock]

    /// Collisions detected in the projected timeline.
    public let collisions: [Collision]

    /// IDs of blocks whose duration was compressed to resolve a collision.
    public let compressedBlockIDs: Set<UUID>

    /// Overall status of the projected timeline.
    public let status: RippleStatus

    /// Per-block start-time delta: `previewStart − originalStart` in seconds.
    ///
    /// Only blocks whose `scheduledStart` would change are included. A
    /// positive value means the block moves later; negative means earlier.
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

/// Produces a ``ShiftPreview`` for a proposed shift **without mutating any
/// live `TimeBlockModel` instances**.
///
/// `ShiftPreviewGenerator` mirrors the four-stage Ripple Engine pipeline but
/// operates entirely on value-type ``PreviewBlock`` copies. This makes it safe
/// to call at any point during a drag gesture or before the user confirms an
/// action, because nothing in the SwiftData store changes until the caller
/// decides to commit.
///
/// ```swift
/// let preview = generator.generatePreview(
///     blocks: allBlocks,
///     blockID: draggedBlock.id,
///     delta: 600          // 10 minutes later
/// )
/// // preview.diffs shows which blocks move and by how much
/// // preview.collisions shows any projected overlaps
/// // allBlocks are completely unchanged
/// ```
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

    /// Generates a projected timeline for the proposed shift without mutating
    /// any live block references.
    ///
    /// Runs the full four-stage pipeline (dependency resolution → shift
    /// propagation → collision detection → compression) on value-type copies
    /// of the input blocks. The live `TimeBlockModel` objects passed in
    /// `blocks` are **never written to**.
    ///
    /// - Parameters:
    ///   - blocks: All live time blocks in the current timeline.
    ///   - blockID: The ID of the block whose start time is being proposed.
    ///   - delta: The proposed time shift in seconds (positive = later,
    ///     negative = earlier).
    /// - Returns: A ``ShiftPreview`` describing the projected state, or a
    ///   preview with `.clean` status and empty diffs if `blockID` is not
    ///   found or `delta` is zero.
    public func generatePreview(
        blocks: [TimeBlockModel],
        blockID: UUID,
        delta: TimeInterval
    ) -> ShiftPreview {
        // Capture original start times before any work so diffs are accurate.
        let originalStarts = blocks.reduce(into: [UUID: Date]()) { dict, block in
            dict[block.id] = block.scheduledStart
        }

        // Copy every live block into a value-type PreviewBlock.
        var preview = blocks.map { PreviewBlock(copying: $0) }
        let sorted = preview.sorted { $0.scheduledStart < $1.scheduledStart }
        preview = sorted

        guard delta != 0,
              let changedIndex = preview.firstIndex(where: { $0.id == blockID }) else {
            return ShiftPreview(
                previewBlocks: preview,
                collisions: [],
                compressedBlockIDs: [],
                status: .clean,
                diffs: [:]
            )
        }

        guard !preview[changedIndex].isPinned else {
            return ShiftPreview(
                previewBlocks: preview,
                collisions: [],
                compressedBlockIDs: [],
                status: .pinnedBlockCannotShift,
                diffs: [:]
            )
        }

        // --- Stage 1: Dependency Resolution ---
        // Build an adjacency list from the preview block IDs (temporal ordering).
        var adjacency = [UUID: [UUID]]()
        for i in 0..<(preview.count - 1) {
            adjacency[preview[i].id, default: []].append(preview[i + 1].id)
        }

        let depResult = dependencyResolver.resolve(adjacency: adjacency, from: blockID)
        let dependentIDs: Set<UUID>
        switch depResult {
        case .success(let ids):
            dependentIDs = ids
        case .failure:
            return ShiftPreview(
                previewBlocks: preview,
                collisions: [],
                compressedBlockIDs: [],
                status: .circularDependency,
                diffs: [:]
            )
        }

        let subsequentFluidIDs = Set(
            preview[(changedIndex + 1)...].filter { !$0.isPinned }.map(\.id)
        )
        let shiftableIDs = subsequentFluidIDs.union(dependentIDs)

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
        let tempBlocks = preview.map { pb -> TimeBlockModel in
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

        let collisions = collisionDetector.detect(blocks: tempBlocks)

        var compressedIDs = Set<UUID>()
        var finalStatus: RippleStatus = collisions.isEmpty ? .clean : .hasCollisions

        for collision in collisions {
            let result = compressionCalculator.compress(blocks: tempBlocks, collision: collision)
            compressedIDs.formUnion(
                result.blocks.filter { $0.id != collision.pinnedBlockID }.map(\.id)
            )
            if result.status == .impossible {
                finalStatus = .impossible
            }
        }

        // Copy the (possibly compressed) temp block state back into PreviewBlocks.
        let tempByID = tempBlocks.reduce(into: [UUID: TimeBlockModel]()) { dict, b in
            dict[b.id] = b
        }
        var finalPreview = preview.map { pb -> PreviewBlock in
            guard let temp = tempByID[pb.id] else { return pb }
            var updated = pb
            updated.scheduledStart = temp.scheduledStart
            updated.duration = temp.duration
            updated.requiresReview = temp.requiresReview
            return updated
        }
        finalPreview.sort { $0.scheduledStart < $1.scheduledStart }

        // --- Diffs: only blocks whose start changed ---
        var diffs = [UUID: TimeInterval]()
        for pb in finalPreview {
            if let original = originalStarts[pb.id] {
                let delta = pb.scheduledStart.timeIntervalSince(original)
                if delta != 0 {
                    diffs[pb.id] = delta
                }
            }
        }

        return ShiftPreview(
            previewBlocks: finalPreview,
            collisions: collisions,
            compressedBlockIDs: compressedIDs,
            status: finalStatus,
            diffs: diffs
        )
    }
}
