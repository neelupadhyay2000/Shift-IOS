import Foundation
import Models

/// Write-side protocol for the Event aggregate.
///
/// Views read events via `@Query`; all mutations route through this protocol so
/// the persistence back-end (SwiftData today, Supabase later) is swappable
/// without touching the UI or the Engine.
@MainActor
public protocol EventRepositing {
    // MARK: – Create
    func insert(_ event: EventModel) async throws

    // MARK: – Read
    func fetch(id: UUID) async throws -> EventModel?
    func fetchAll() async throws -> [EventModel]

    // MARK: – Delete
    func delete(_ event: EventModel) async throws

    // MARK: – Persist
    /// Flush all pending mutations to the underlying store.
    func save() async throws
}
