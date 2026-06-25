import Foundation
import Models
import Services

// Outbox repositories: each mutation writes to the local SwiftData store
// (optimistic, local-first) and then appends an `OutboxEntry` via the shared
// `OutboxCoordinator`. Reads come straight from the local cache (the runtime
// source of truth that `@Query` observes). Nothing here touches the network —
// the SyncEngine flush drains the queue to Supabase later.

@MainActor
struct OutboxEventRepository: EventRepositing {
    let local: any EventRepositing
    let coordinator: OutboxCoordinator

    func insert(_ event: EventModel) async throws {
        try await coordinator.write(.insert, event) { try await local.insert(event) }
    }

    func fetch(id: UUID) async throws -> EventModel? {
        try await local.fetch(id: id)
    }

    func fetchAll() async throws -> [EventModel] {
        try await local.fetchAll()
    }

    func delete(_ event: EventModel) async throws {
        try await coordinator.write(.delete, event) { try await local.delete(event) }
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
        try await coordinator.write(.insert, track) { try await local.insert(track, into: event) }
    }

    func fetch(id: UUID) async throws -> TimelineTrack? {
        try await local.fetch(id: id)
    }

    func fetchAll(for event: EventModel) async throws -> [TimelineTrack] {
        try await local.fetchAll(for: event)
    }

    func delete(_ track: TimelineTrack) async throws {
        try await coordinator.write(.delete, track) { try await local.delete(track) }
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
        try await coordinator.write(.insert, block) { try await local.insert(block, into: track) }
    }

    func fetch(id: UUID) async throws -> TimeBlockModel? {
        try await local.fetch(id: id)
    }

    func fetchAll(for track: TimelineTrack) async throws -> [TimeBlockModel] {
        try await local.fetchAll(for: track)
    }

    func delete(_ block: TimeBlockModel) async throws {
        try await coordinator.write(.delete, block) { try await local.delete(block) }
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
        try await coordinator.write(.insert, vendor) { try await local.insert(vendor, into: event) }
    }

    func fetch(id: UUID) async throws -> VendorModel? {
        try await local.fetch(id: id)
    }

    func fetchAll(for event: EventModel) async throws -> [VendorModel] {
        try await local.fetchAll(for: event)
    }

    func delete(_ vendor: VendorModel) async throws {
        try await coordinator.write(.delete, vendor) { try await local.delete(vendor) }
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
        try await coordinator.write(.insert, record) { try await local.insert(record, into: event) }
    }

    func fetch(id: UUID) async throws -> ShiftRecord? {
        try await local.fetch(id: id)
    }

    func fetchAll(for event: EventModel) async throws -> [ShiftRecord] {
        try await local.fetchAll(for: event)
    }

    func delete(_ record: ShiftRecord) async throws {
        try await coordinator.write(.delete, record) { try await local.delete(record) }
    }

    func save() async throws {
        try coordinator.save()
    }
}
