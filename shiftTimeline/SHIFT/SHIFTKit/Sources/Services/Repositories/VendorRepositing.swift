import Foundation
import Models

/// Write-side protocol for the VendorModel aggregate.
///
/// Block-assignment operations are declared here because the
/// `VendorModel.assignedBlocks` many-to-many relationship is owned
/// by the vendor aggregate.
@MainActor
public protocol VendorRepositing {
    // MARK: – Create
    func insert(_ vendor: VendorModel, into event: EventModel) async throws

    // MARK: – Read
    func fetch(id: UUID) async throws -> VendorModel?
    func fetchAll(for event: EventModel) async throws -> [VendorModel]

    // MARK: – Delete
    func delete(_ vendor: VendorModel) async throws

    // MARK: – Persist
    func save() async throws

    // MARK: – Block-assignment relationships
    func assign(_ vendor: VendorModel, to block: TimeBlockModel) async throws
    func unassign(_ vendor: VendorModel, from block: TimeBlockModel) async throws
}
