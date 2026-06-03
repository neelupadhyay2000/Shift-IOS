import Foundation
import Models

/// Write-side protocol for the TimelineTrack aggregate.
///
/// Callers pass the owning `EventModel` on insert so each back-end can
/// establish the parent–child relationship in its own way.
@MainActor
public protocol TrackRepositing {
    // MARK: – Create
    func insert(_ track: TimelineTrack, into event: EventModel) async throws

    // MARK: – Read
    func fetch(id: UUID) async throws -> TimelineTrack?
    func fetchAll(for event: EventModel) async throws -> [TimelineTrack]

    // MARK: – Delete
    func delete(_ track: TimelineTrack) async throws

    // MARK: – Persist
    func save() async throws
}
