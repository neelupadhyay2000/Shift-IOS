import Foundation
import Models
import SwiftData

@MainActor
public final class SwiftDataBlockRepository: BlockRepositing {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func insert(_ block: TimeBlockModel, into track: TimelineTrack) async throws {
        block.track = track
        context.insert(block)
    }

    public func fetch(id: UUID) async throws -> TimeBlockModel? {
        var descriptor = FetchDescriptor<TimeBlockModel>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func fetchAll(for track: TimelineTrack) async throws -> [TimeBlockModel] {
        (track.blocks ?? []).sorted { $0.scheduledStart < $1.scheduledStart }
    }

    public func delete(_ block: TimeBlockModel) async throws {
        context.delete(block)
    }

    public func save() async throws {
        try context.save()
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
