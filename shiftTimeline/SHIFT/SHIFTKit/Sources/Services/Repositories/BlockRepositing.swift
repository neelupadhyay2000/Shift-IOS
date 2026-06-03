import Foundation
import Models

/// Write-side protocol for the TimeBlockModel aggregate.
///
/// Callers pass the owning `TimelineTrack` on insert.
/// Dependency management is declared here because the self-referencing
/// `dependencies / dependents` relationship is internal to this aggregate.
@MainActor
public protocol BlockRepositing {
    // MARK: – Create
    func insert(_ block: TimeBlockModel, into track: TimelineTrack) async throws

    // MARK: – Read
    func fetch(id: UUID) async throws -> TimeBlockModel?
    func fetchAll(for track: TimelineTrack) async throws -> [TimeBlockModel]

    // MARK: – Delete
    func delete(_ block: TimeBlockModel) async throws

    // MARK: – Persist
    func save() async throws

    // MARK: – Dependency relationships
    func addDependency(_ dependency: TimeBlockModel, to block: TimeBlockModel) async throws
    func removeDependency(_ dependency: TimeBlockModel, from block: TimeBlockModel) async throws
}
