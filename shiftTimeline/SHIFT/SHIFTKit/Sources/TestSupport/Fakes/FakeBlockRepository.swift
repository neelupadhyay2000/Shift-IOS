import Foundation
import Models
import Services

/// In-memory fake for `BlockRepositing`.
@MainActor
public final class FakeBlockRepository: BlockRepositing {

    public private(set) var blocks: [TimeBlockModel] = []
    public private(set) var saveCallCount = 0

    public init() {}

    public func insert(_ block: TimeBlockModel, into track: TimelineTrack) async throws {
        block.track = track
        blocks.append(block)
    }

    public func fetch(id: UUID) async throws -> TimeBlockModel? {
        blocks.first { $0.id == id }
    }

    public func fetchAll(for track: TimelineTrack) async throws -> [TimeBlockModel] {
        blocks
            .filter { $0.track?.id == track.id }
            .sorted { $0.scheduledStart < $1.scheduledStart }
    }

    public func delete(_ block: TimeBlockModel) async throws {
        blocks.removeAll { $0.id == block.id }
    }

    public func save() async throws {
        saveCallCount += 1
    }

    public func addDependency(_ dependency: TimeBlockModel, to block: TimeBlockModel) async throws {
        var deps = block.dependencies ?? []
        guard !deps.contains(where: { $0.id == dependency.id }) else { return }
        deps.append(dependency)
        block.dependencies = deps
    }

    public func removeDependency(_ dependency: TimeBlockModel, from block: TimeBlockModel) async throws {
        block.dependencies?.removeAll { $0.id == dependency.id }
    }
}
