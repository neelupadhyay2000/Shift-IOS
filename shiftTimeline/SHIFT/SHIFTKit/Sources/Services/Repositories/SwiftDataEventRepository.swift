import Foundation
import Models
import SwiftData

@MainActor
public final class SwiftDataEventRepository: EventRepositing {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func insert(_ event: EventModel) async throws {
        context.insert(event)
    }

    public func fetch(id: UUID) async throws -> EventModel? {
        var descriptor = FetchDescriptor<EventModel>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func fetchAll() async throws -> [EventModel] {
        try context.fetch(FetchDescriptor<EventModel>())
    }

    public func delete(_ event: EventModel) async throws {
        context.delete(event)
    }

    public func save() async throws {
        try context.save()
    }
}
