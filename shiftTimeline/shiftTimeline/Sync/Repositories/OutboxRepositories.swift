import Foundation
import Models
import Services

// Outbox repositories: each mutation writes to the local SwiftData store
// (optimistic, local-first) and then appends an `OutboxEntry` via the shared
// `OutboxCoordinator`. Reads come straight from the local cache (the runtime
// source of truth that `@Query` observes). Nothing here touches the network —
// the SyncEngine flush (SHIFT-603) drains the queue to Supabase later. This is
// the offline replacement for the E12 write-through layer.

@MainActor
struct OutboxEventRepository: EventRepositing {
    let local: any EventRepositing
    let coordinator: OutboxCoordinator

    func insert(_ event: EventModel) async throws {
        try await local.insert(event)
        coordinator.enqueueWrite(.insert, event)
    }

    func fetch(id: UUID) async throws -> EventModel? {
        try await local.fetch(id: id)
    }

    func fetchAll() async throws -> [EventModel] {
        try await local.fetchAll()
    }

    func delete(_ event: EventModel) async throws {
        try await local.delete(event)
        coordinator.enqueueWrite(.delete, event)
    }

    func save() async throws {
        try coordinator.save()
    }
}

@MainActor
struct OutboxTrackRepository: TrackRepositing {
    let local: any TrackRepositing
    let coordinator: OutboxCoordinator

    func insert(_ track: TimelineTrack, into event: EventModel) async throws {
        try await local.insert(track, into: event)
        coordinator.enqueueWrite(.insert, track)
    }

    func fetch(id: UUID) async throws -> TimelineTrack? {
        try await local.fetch(id: id)
    }

    func fetchAll(for event: EventModel) async throws -> [TimelineTrack] {
        try await local.fetchAll(for: event)
    }

    func delete(_ track: TimelineTrack) async throws {
        try await local.delete(track)
        coordinator.enqueueWrite(.delete, track)
    }

    func save() async throws {
        try coordinator.save()
    }
}

@MainActor
struct OutboxBlockRepository: BlockRepositing {
    let local: any BlockRepositing
    let coordinator: OutboxCoordinator

    func insert(_ block: TimeBlockModel, into track: TimelineTrack) async throws {
        try await local.insert(block, into: track)
        coordinator.enqueueWrite(.insert, block)
    }

    func fetch(id: UUID) async throws -> TimeBlockModel? {
        try await local.fetch(id: id)
    }

    func fetchAll(for track: TimelineTrack) async throws -> [TimeBlockModel] {
        try await local.fetchAll(for: track)
    }

    func delete(_ block: TimeBlockModel) async throws {
        try await local.delete(block)
        coordinator.enqueueWrite(.delete, block)
    }

    func save() async throws {
        try coordinator.save()
    }

    func addDependency(_ dependency: TimeBlockModel, to block: TimeBlockModel) async throws {
        try await local.addDependency(dependency, to: block)
        coordinator.enqueueDependency(.insert, block: block, dependsOn: dependency)
    }

    func removeDependency(_ dependency: TimeBlockModel, from block: TimeBlockModel) async throws {
        try await local.removeDependency(dependency, from: block)
        coordinator.enqueueDependency(.delete, block: block, dependsOn: dependency)
    }
}

@MainActor
struct OutboxVendorRepository: VendorRepositing {
    let local: any VendorRepositing
    let coordinator: OutboxCoordinator

    func insert(_ vendor: VendorModel, into event: EventModel) async throws {
        try await local.insert(vendor, into: event)
        coordinator.enqueueWrite(.insert, vendor)
    }

    func fetch(id: UUID) async throws -> VendorModel? {
        try await local.fetch(id: id)
    }

    func fetchAll(for event: EventModel) async throws -> [VendorModel] {
        try await local.fetchAll(for: event)
    }

    func delete(_ vendor: VendorModel) async throws {
        try await local.delete(vendor)
        coordinator.enqueueWrite(.delete, vendor)
    }

    func save() async throws {
        try coordinator.save()
    }

    func assign(_ vendor: VendorModel, to block: TimeBlockModel) async throws {
        try await local.assign(vendor, to: block)
        coordinator.enqueueAssignment(.insert, vendor: vendor, block: block)
    }

    func unassign(_ vendor: VendorModel, from block: TimeBlockModel) async throws {
        try await local.unassign(vendor, from: block)
        coordinator.enqueueAssignment(.delete, vendor: vendor, block: block)
    }
}

@MainActor
struct OutboxShiftRecordRepository: ShiftRecordRepositing {
    let local: any ShiftRecordRepositing
    let coordinator: OutboxCoordinator

    func insert(_ record: ShiftRecord, into event: EventModel) async throws {
        try await local.insert(record, into: event)
        coordinator.enqueueWrite(.insert, record)
    }

    func fetch(id: UUID) async throws -> ShiftRecord? {
        try await local.fetch(id: id)
    }

    func fetchAll(for event: EventModel) async throws -> [ShiftRecord] {
        try await local.fetchAll(for: event)
    }

    func delete(_ record: ShiftRecord) async throws {
        try await local.delete(record)
        coordinator.enqueueWrite(.delete, record)
    }

    func save() async throws {
        try coordinator.save()
    }
}
