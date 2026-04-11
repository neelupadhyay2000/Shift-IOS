import Foundation
import Models

// MARK: - CollisionDetector

/// Scans a set of time blocks for temporal overlaps between Fluid and Pinned blocks.
///
/// This is Stage 3 of the Ripple Engine pipeline. It is a pure, stateless struct
/// with no side effects and no SwiftData imports.
///
/// ## Placeholder
/// `detect(blocks:)` currently returns an empty array. Full overlap detection
/// will be implemented in SHIFT-201.
public struct CollisionDetector: Sendable {

    public init() {}

    /// Detects collisions between Fluid and Pinned blocks.
    ///
    /// A collision occurs when a Fluid block's window `(scheduledStart, scheduledStart + duration)`
    /// overlaps the `scheduledStart` of a later Pinned block.
    ///
    /// - Parameter blocks: All time blocks in the current timeline.
    /// - Returns: An array of ``Collision`` values describing every overlap found.
    ///   Returns an empty array in the current placeholder implementation.
    public func detect(blocks: [TimeBlockModel]) -> [Collision] {
        // SHIFT-201: implement full overlap detection
        return []
    }
}
