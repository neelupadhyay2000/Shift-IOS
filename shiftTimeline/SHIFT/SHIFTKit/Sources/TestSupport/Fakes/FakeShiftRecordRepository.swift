import Foundation
import Models
import Services

/// In-memory fake for `ShiftRecordRepositing`.
@MainActor
public final class FakeShiftRecordRepository: ShiftRecordRepositing {

    public private(set) var records: [ShiftRecord] = []
    public private(set) var saveCallCount = 0

    public init() {}

    public func insert(_ record: ShiftRecord, into event: EventModel) async throws {
        record.event = event
        records.append(record)
    }

    public func fetch(id: UUID) async throws -> ShiftRecord? {
        records.first { $0.id == id }
    }

    public func fetchAll(for event: EventModel) async throws -> [ShiftRecord] {
        records
            .filter { $0.event?.id == event.id }
            .sorted { $0.timestamp < $1.timestamp }
    }

    public func delete(_ record: ShiftRecord) async throws {
        records.removeAll { $0.id == record.id }
    }

    public func save() async throws {
        saveCallCount += 1
    }
}
