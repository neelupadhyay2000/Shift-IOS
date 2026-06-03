import Foundation
import Models

/// Write-side protocol for the ShiftRecord aggregate.
///
/// ShiftRecords are append-only audit entries; they have no relationship
/// operations beyond belonging to an event and optionally referencing
/// a source block.
@MainActor
public protocol ShiftRecordRepositing {
    // MARK: – Create
    func insert(_ record: ShiftRecord, into event: EventModel) async throws

    // MARK: – Read
    func fetch(id: UUID) async throws -> ShiftRecord?
    func fetchAll(for event: EventModel) async throws -> [ShiftRecord]

    // MARK: – Delete
    func delete(_ record: ShiftRecord) async throws

    // MARK: – Persist
    func save() async throws
}
