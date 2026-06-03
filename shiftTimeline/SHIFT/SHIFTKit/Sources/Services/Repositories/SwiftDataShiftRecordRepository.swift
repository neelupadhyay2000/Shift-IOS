import Foundation
import Models
import SwiftData

@MainActor
public final class SwiftDataShiftRecordRepository: ShiftRecordRepositing {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Registers `record` with the context and wires it to `event`.
    /// Set `record.sourceBlock` on the record before calling this if the shift
    /// was triggered by a specific block.
    public func insert(_ record: ShiftRecord, into event: EventModel) async throws {
        record.event = event
        context.insert(record)
    }

    public func fetch(id: UUID) async throws -> ShiftRecord? {
        var descriptor = FetchDescriptor<ShiftRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func fetchAll(for event: EventModel) async throws -> [ShiftRecord] {
        (event.shiftRecords ?? []).sorted { $0.timestamp < $1.timestamp }
    }

    public func delete(_ record: ShiftRecord) async throws {
        context.delete(record)
    }

    public func save() async throws {
        try context.save()
    }
}
