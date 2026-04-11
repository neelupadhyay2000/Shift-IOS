import Foundation
import Models

/// Resolves ordering dependencies between time blocks to determine which
/// blocks are affected by a shift operation.
///
/// Dependencies are derived from temporal ordering: block B depends on block A
/// if B is the next block (by `scheduledStart`) after A. This forms a forward
/// chain that may branch when multiple blocks share the same `scheduledStart`.
public struct DependencyResolver: Sendable {
    public init() {}

    /// Determines the set of block IDs downstream of the shifted block via BFS.
    ///
    /// Builds a forward adjacency list from the sorted timeline, then walks
    /// all reachable nodes from `shiftedBlockID`.
    ///
    /// - Parameters:
    ///   - blocks: All time blocks in the timeline.
    ///   - shiftedBlockID: The ID of the block that was shifted.
    /// - Returns: A set of downstream block IDs (excluding `shiftedBlockID`),
    ///   or an error if resolution fails.
    public func resolve(blocks: [TimeBlockModel], shiftedBlockID: UUID) -> Result<Set<UUID>, SHIFTError> {
        guard !blocks.isEmpty else { return .success([]) }

        let sorted = blocks.sorted { $0.scheduledStart < $1.scheduledStart }

        // Build forward adjacency list: each block points to the block(s)
        // immediately after it in sorted order.
        var adjacency = [UUID: [UUID]]()
        for i in 0..<(sorted.count - 1) {
            adjacency[sorted[i].id, default: []].append(sorted[i + 1].id)
        }

        // If shiftedBlockID isn't in the graph, return empty.
        guard sorted.contains(where: { $0.id == shiftedBlockID }) else {
            return .success([])
        }

        // BFS from shiftedBlockID to collect all downstream dependents.
        var visited = Set<UUID>()
        var queue = adjacency[shiftedBlockID] ?? []

        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard visited.insert(current).inserted else { continue }
            queue.append(contentsOf: adjacency[current] ?? [])
        }

        return .success(visited)
    }
}
