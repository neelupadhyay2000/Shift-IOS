import Foundation
import Models
import Services

// Write-through repositories: each mutation hits the local SwiftData store
// (optimistic, local-first) and then mirrors to Supabase while online. Reads
// come from the local cache (the runtime source of truth; `@Query` reads it).
// `save()` defers to the shared `WriteThroughCoordinator`, which flushes the
// context and mirrors edits / bypass-inserts. Offline queueing is E13.

@MainActor
struct WriteThroughEventRepository: EventRepositing {
    let local: any EventRepositing
    let remote: any EventRepositing
    let coordinator: WriteThroughCoordinator

    func insert(_ event: EventModel) async throws {
        try await local.insert(event)
        try await remote.insert(event)
    }

    func fetch(id: UUID) async throws -> EventModel? {
        try await local.fetch(id: id)
    }

    func fetchAll() async throws -> [EventModel] {
        try await local.fetchAll()
    }

    func delete(_ event: EventModel) async throws {
        try await local.delete(event)
        try await remote.delete(event)
    }

    func save() async throws {
        try await coordinator.save()
    }
}

@MainActor
struct WriteThroughTrackRepository: TrackRepositing {
    let local: any TrackRepositing
    let remote: any TrackRepositing
    let coordinator: WriteThroughCoordinator

    func insert(_ track: TimelineTrack, into event: EventModel) async throws {
        try await local.insert(track, into: event)
        try await remote.insert(track, into: event)
    }

    func fetch(id: UUID) async throws -> TimelineTrack? {
        try await local.fetch(id: id)
    }

    func fetchAll(for event: EventModel) async throws -> [TimelineTrack] {
        try await local.fetchAll(for: event)
    }

    func delete(_ track: TimelineTrack) async throws {
        try await local.delete(track)
        try await remote.delete(track)
    }

    func save() async throws {
        try await coordinator.save()
    }
}

@MainActor
struct WriteThroughBlockRepository: BlockRepositing {
    let local: any BlockRepositing
    let remote: any BlockRepositing
    let coordinator: WriteThroughCoordinator

    func insert(_ block: TimeBlockModel, into track: TimelineTrack) async throws {
        try await local.insert(block, into: track)
        try await remote.insert(block, into: track)
    }

    func fetch(id: UUID) async throws -> TimeBlockModel? {
        try await local.fetch(id: id)
    }

    func fetchAll(for track: TimelineTrack) async throws -> [TimeBlockModel] {
        try await local.fetchAll(for: track)
    }

    func delete(_ block: TimeBlockModel) async throws {
        try await local.delete(block)
        try await remote.delete(block)
    }

    func save() async throws {
        try await coordinator.save()
    }

    func addDependency(_ dependency: TimeBlockModel, to block: TimeBlockModel) async throws {
        try await local.addDependency(dependency, to: block)
        try await remote.addDependency(dependency, to: block)
    }

    func removeDependency(_ dependency: TimeBlockModel, from block: TimeBlockModel) async throws {
        try await local.removeDependency(dependency, from: block)
        try await remote.removeDependency(dependency, from: block)
    }
}

@MainActor
struct WriteThroughVendorRepository: VendorRepositing {
    let local: any VendorRepositing
    let remote: any VendorRepositing
    let coordinator: WriteThroughCoordinator

    func insert(_ vendor: VendorModel, into event: EventModel) async throws {
        try await local.insert(vendor, into: event)
        try await remote.insert(vendor, into: event)
    }

    func fetch(id: UUID) async throws -> VendorModel? {
        try await local.fetch(id: id)
    }

    func fetchAll(for event: EventModel) async throws -> [VendorModel] {
        try await local.fetchAll(for: event)
    }

    func delete(_ vendor: VendorModel) async throws {
        try await local.delete(vendor)
        try await remote.delete(vendor)
    }

    func save() async throws {
        try await coordinator.save()
    }

    func assign(_ vendor: VendorModel, to block: TimeBlockModel) async throws {
        try await local.assign(vendor, to: block)
        try await remote.assign(vendor, to: block)
    }

    func unassign(_ vendor: VendorModel, from block: TimeBlockModel) async throws {
        try await local.unassign(vendor, from: block)
        try await remote.unassign(vendor, from: block)
    }
}

@MainActor
struct WriteThroughShiftRecordRepository: ShiftRecordRepositing {
    let local: any ShiftRecordRepositing
    let remote: any ShiftRecordRepositing
    let coordinator: WriteThroughCoordinator

    func insert(_ record: ShiftRecord, into event: EventModel) async throws {
        try await local.insert(record, into: event)
        try await remote.insert(record, into: event)
    }

    func fetch(id: UUID) async throws -> ShiftRecord? {
        try await local.fetch(id: id)
    }

    func fetchAll(for event: EventModel) async throws -> [ShiftRecord] {
        try await local.fetchAll(for: event)
    }

    func delete(_ record: ShiftRecord) async throws {
        try await local.delete(record)
        try await remote.delete(record)
    }

    func save() async throws {
        try await coordinator.save()
    }
}
