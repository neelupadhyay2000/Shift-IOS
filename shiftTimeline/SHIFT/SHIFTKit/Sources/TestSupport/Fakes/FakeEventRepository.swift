import Foundation
import Models
import Services

/// In-memory fake for `EventRepositing`.
///
/// Stores events in a plain array — no SwiftData container required.
/// Exposes `saveCallCount` so tests can assert that save was requested.
@MainActor
public final class FakeEventRepository: EventRepositing {

    public private(set) var events: [EventModel] = []
    public private(set) var saveCallCount = 0

    public init() {}

    public func insert(_ event: EventModel) async throws {
        events.append(event)
    }

    public func fetch(id: UUID) async throws -> EventModel? {
        events.first { $0.id == id }
    }

    public func fetchAll() async throws -> [EventModel] {
        events
    }

    public func delete(_ event: EventModel) async throws {
        events.removeAll { $0.id == event.id }
    }

    public func save() async throws {
        saveCallCount += 1
    }
}
