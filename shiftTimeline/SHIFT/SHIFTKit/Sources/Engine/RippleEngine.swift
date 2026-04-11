import Foundation
import Models

// MARK: - Dependencies

/// Resolves ordering dependencies between time blocks.
public struct DependencyResolver: Sendable {
    public init() {}
}

/// Detects temporal collisions (overlaps) between time blocks.
public struct CollisionDetector: Sendable {
    public init() {}
}

/// Calculates how blocks can be compressed toward their minimum duration.
public struct CompressionCalculator: Sendable {
    public init() {}
}

// MARK: - RippleEngine

/// A stateless engine that propagates a time-delta change across a set of
/// time blocks, detecting collisions and compressing where necessary.
public struct RippleEngine: Sendable {
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

    /// Recalculates the timeline after a block's scheduled time changes.
    ///
    /// - Parameters:
    ///   - blocks: All time blocks in the timeline.
    ///   - changedBlockID: The ID of the block whose time changed.
    ///   - delta: The time shift in seconds (positive = later, negative = earlier).
    /// - Returns: A ``RippleResult`` describing the adjusted timeline state.
    public func recalculate(
        blocks: [TimeBlockModel],
        changedBlockID: UUID,
        delta: TimeInterval
    ) -> RippleResult {
        guard delta > 0 else {
            return RippleResult(blocks: blocks, status: .clean)
        }

        let sorted = blocks.sorted { $0.scheduledStart < $1.scheduledStart }

        guard let changedIndex = sorted.firstIndex(where: { $0.id == changedBlockID }) else {
            return RippleResult(blocks: sorted, status: .clean)
        }

        // Shift the changed block itself.
        sorted[changedIndex].scheduledStart = sorted[changedIndex]
            .scheduledStart.addingTimeInterval(delta)

        // Shift all subsequent Fluid (non-pinned) blocks forward by delta.
        for index in (changedIndex + 1)..<sorted.count where !sorted[index].isPinned {
            sorted[index].scheduledStart = sorted[index]
                .scheduledStart.addingTimeInterval(delta)
        }

        return RippleResult(blocks: sorted, status: .clean)
    }
}
