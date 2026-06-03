import Foundation
import Models
import SwiftData

@MainActor
public final class SwiftDataVendorRepository: VendorRepositing {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func insert(_ vendor: VendorModel, into event: EventModel) async throws {
        vendor.event = event
        context.insert(vendor)
    }

    public func fetch(id: UUID) async throws -> VendorModel? {
        var descriptor = FetchDescriptor<VendorModel>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func fetchAll(for event: EventModel) async throws -> [VendorModel] {
        event.vendors ?? []
    }

    public func delete(_ vendor: VendorModel) async throws {
        context.delete(vendor)
    }

    public func save() async throws {
        try context.save()
    }

    public func assign(_ vendor: VendorModel, to block: TimeBlockModel) async throws {
        var assigned = block.vendors ?? []
        guard !assigned.contains(where: { $0.id == vendor.id }) else { return }
        assigned.append(vendor)
        block.vendors = assigned
    }

    public func unassign(_ vendor: VendorModel, from block: TimeBlockModel) async throws {
        block.vendors?.removeAll { $0.id == vendor.id }
    }
}
