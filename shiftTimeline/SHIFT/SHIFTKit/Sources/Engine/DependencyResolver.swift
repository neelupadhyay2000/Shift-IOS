import Foundation
import Models

/// Resolves which blocks are downstream of a shifted block via BFS over a temporal adjacency list.
public struct DependencyResolver: Sendable {
    public init() {}

    /// Returns downstream block IDs via BFS from the sorted timeline. Returns `.failure` on cycle detection.
    public func resolve(blocks: [TimeBlockModel], shiftedBlockID: UUID) -> Result<Set<UUID>, SHIFTError> {
        let sorted = blocks.sorted { $0.scheduledStart < $1.scheduledStart }
        return resolve(sortedBlocks: sorted, shiftedBlockID: shiftedBlockID)
    }

    /// Pre-sorted variant — skips O(n log n) sort.
    public func resolve(sortedBlocks sorted: [TimeBlockModel], shiftedBlockID: UUID) -> Result<Set<UUID>, SHIFTError> {
        guard !sorted.isEmpty else { return .success([]) }

        // Build forward adjacency list from temporal ordering.
        var adjacency = [UUID: [UUID]]()
        for i in 0..<(sorted.count - 1) {
            adjacency[sorted[i].id, default: []].append(sorted[i + 1].id)
        }

        return resolve(adjacency: adjacency, from: shiftedBlockID)
    }

    /// BFS over an explicit adjacency list. Returns `.failure` on cycle detection.
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
