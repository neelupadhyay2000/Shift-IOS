import Foundation
import Models

/// Resolves ordering dependencies between time blocks to determine which
/// blocks are affected by a shift operation.
///
/// Dependencies can be derived from temporal ordering (default) or provided
/// as an explicit adjacency list for richer dependency graphs.
public struct DependencyResolver: Sendable {
    public init() {}

    /// Determines the set of block IDs downstream of the shifted block via BFS.
    ///
    /// Builds a forward adjacency list from the sorted timeline, then walks
    /// all reachable nodes from `shiftedBlockID`. Detects cycles — if BFS
    /// encounters `shiftedBlockID` as a downstream node, returns
    /// `.failure(.circularDependency(blockID:))`.
    ///
    /// - Parameters:
    ///   - blocks: All time blocks in the timeline.
    ///   - shiftedBlockID: The ID of the block that was shifted.
    /// - Returns: A set of downstream block IDs (excluding `shiftedBlockID`),
    ///   or an error if a cycle is detected.
    public func resolve(blocks: [TimeBlockModel], shiftedBlockID: UUID) -> Result<Set<UUID>, SHIFTError> {
        let sorted = blocks.sorted { $0.scheduledStart < $1.scheduledStart }
        return resolve(sortedBlocks: sorted, shiftedBlockID: shiftedBlockID)
    }

    /// Pre-sorted variant — avoids an O(n log n) sort when the caller has
    /// already sorted blocks by `scheduledStart`.
    public func resolve(sortedBlocks sorted: [TimeBlockModel], shiftedBlockID: UUID) -> Result<Set<UUID>, SHIFTError> {
        guard !sorted.isEmpty else { return .success([]) }

        // Build forward adjacency list from temporal ordering.
        var adjacency = [UUID: [UUID]]()
        for i in 0..<(sorted.count - 1) {
            adjacency[sorted[i].id, default: []].append(sorted[i + 1].id)
        }

        return resolve(adjacency: adjacency, from: shiftedBlockID)
    }

    /// Determines the set of block IDs downstream of the shifted block via BFS
    /// over an explicit adjacency list.
    ///
    /// - Parameters:
    ///   - adjacency: A forward adjacency list mapping each block ID to its
    ///     direct dependents.
    ///   - shiftedBlockID: The ID of the block that was shifted.
    /// - Returns: A set of downstream block IDs (excluding `shiftedBlockID`),
    ///   or `.failure(.circularDependency(blockID:))` if a cycle is detected.
    public func resolve(adjacency: [UUID: [UUID]], from shiftedBlockID: UUID) -> Result<Set<UUID>, SHIFTError> {
        var visited = Set<UUID>()
        var queue = adjacency[shiftedBlockID] ?? []
        var i = 0

        while i < queue.count {
            let current = queue[i]
            i += 1

            // Cycle: BFS reached the origin node.
            if current == shiftedBlockID {
                return .failure(.circularDependency(blockID: shiftedBlockID))
            }

            guard visited.insert(current).inserted else { continue }
            queue.append(contentsOf: adjacency[current] ?? [])
        }

        return .success(visited)
    }
}
