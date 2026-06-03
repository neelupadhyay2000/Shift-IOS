import Foundation
import Models
import Services

/// In-memory fake for `VendorRepositing`.
@MainActor
public final class FakeVendorRepository: VendorRepositing {

    public private(set) var vendors: [VendorModel] = []
    public private(set) var saveCallCount = 0

    public init() {}

    public func insert(_ vendor: VendorModel, into event: EventModel) async throws {
        vendor.event = event
        vendors.append(vendor)
    }

    public func fetch(id: UUID) async throws -> VendorModel? {
        vendors.first { $0.id == id }
    }

    public func fetchAll(for event: EventModel) async throws -> [VendorModel] {
        vendors.filter { $0.event?.id == event.id }
    }

    public func delete(_ vendor: VendorModel) async throws {
        vendors.removeAll { $0.id == vendor.id }
    }

    public func save() async throws {
        saveCallCount += 1
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
