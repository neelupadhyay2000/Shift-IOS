import Foundation
import Models
import Services

// Write-through repositories: each mutation hits the local SwiftData store
// (optimistic, local-first) and then mirrors to Supabase while online. Reads
// come from the local cache (the runtime source of truth; `@Query` reads it).
// Every remote call goes through `coordinator.mirrorRemoteWrite`, which records
// failures to diagnostics instead of rethrowing — so a remote error never fails
// the user's local-first action and is never silently dropped. `save()` defers
// to the coordinator, which flushes the context and mirrors edits /
// bypass-inserts. Offline queueing is layered on by the Outbox.

@MainActor
struct WriteThroughEventRepository: EventRepositing {
    let local: any EventRepositing
    let remote: any EventRepositing
    let coordinator: WriteThroughCoordinator

    func insert(_ event: EventModel) async throws {
        try await local.insert(event)
        await coordinator.mirrorRemoteWrite("insert", "events", id: event.id) {
            try await self.remote.insert(event)
        }
    }

    func fetch(id: UUID) async throws -> EventModel? {
        try await local.fetch(id: id)
    }

    func fetchAll() async throws -> [EventModel] {
        try await local.fetchAll()
    }

    func delete(_ event: EventModel) async throws {
        try await local.delete(event)
        await coordinator.mirrorRemoteWrite("delete", "events", id: event.id) {
            try await self.remote.delete(event)
        }
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
        await coordinator.mirrorRemoteWrite("insert", "tracks", id: track.id) {
            try await self.remote.insert(track, into: event)
        }
    }

    func fetch(id: UUID) async throws -> TimelineTrack? {
        try await local.fetch(id: id)
    }

    func fetchAll(for event: EventModel) async throws -> [TimelineTrack] {
        try await local.fetchAll(for: event)
    }

    func delete(_ track: TimelineTrack) async throws {
        try await local.delete(track)
        await coordinator.mirrorRemoteWrite("delete", "tracks", id: track.id) {
            try await self.remote.delete(track)
        }
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
        await coordinator.mirrorRemoteWrite("insert", "blocks", id: block.id) {
            try await self.remote.insert(block, into: track)
        }
    }

    func fetch(id: UUID) async throws -> TimeBlockModel? {
        try await local.fetch(id: id)
    }

    func fetchAll(for track: TimelineTrack) async throws -> [TimeBlockModel] {
        try await local.fetchAll(for: track)
    }

    func delete(_ block: TimeBlockModel) async throws {
        try await local.delete(block)
        await coordinator.mirrorRemoteWrite("delete", "blocks", id: block.id) {
            try await self.remote.delete(block)
        }
    }

    func save() async throws {
        try await coordinator.save()
    }

    func addDependency(_ dependency: TimeBlockModel, to block: TimeBlockModel) async throws {
        try await local.addDependency(dependency, to: block)
        await coordinator.mirrorRemoteWrite(
            "insert", "block_dependencies", id: block.id,
            detail: ["dependsOn": dependency.id.uuidString]
        ) {
            try await self.remote.addDependency(dependency, to: block)
        }
    }

    func removeDependency(_ dependency: TimeBlockModel, from block: TimeBlockModel) async throws {
        try await local.removeDependency(dependency, from: block)
        await coordinator.mirrorRemoteWrite(
            "delete", "block_dependencies", id: block.id,
            detail: ["dependsOn": dependency.id.uuidString]
        ) {
            try await self.remote.removeDependency(dependency, from: block)
        }
    }
}

@MainActor
struct WriteThroughVendorRepository: VendorRepositing {
    let local: any VendorRepositing
    let remote: any VendorRepositing
    let coordinator: WriteThroughCoordinator

    func insert(_ vendor: VendorModel, into event: EventModel) async throws {
        try await local.insert(vendor, into: event)
        await coordinator.mirrorRemoteWrite("insert", "event_vendors", id: vendor.id) {
            try await self.remote.insert(vendor, into: event)
        }
    }

    func fetch(id: UUID) async throws -> VendorModel? {
        try await local.fetch(id: id)
    }

    func fetchAll(for event: EventModel) async throws -> [VendorModel] {
        try await local.fetchAll(for: event)
    }

    func delete(_ vendor: VendorModel) async throws {
        try await local.delete(vendor)
        await coordinator.mirrorRemoteWrite("delete", "event_vendors", id: vendor.id) {
            try await self.remote.delete(vendor)
        }
    }

    func save() async throws {
        try await coordinator.save()
    }

    func assign(_ vendor: VendorModel, to block: TimeBlockModel) async throws {
        try await local.assign(vendor, to: block)
        await coordinator.mirrorRemoteWrite(
            "insert", "block_vendors", id: block.id,
            detail: ["vendor": vendor.id.uuidString]
        ) {
            try await self.remote.assign(vendor, to: block)
        }
    }

    func unassign(_ vendor: VendorModel, from block: TimeBlockModel) async throws {
        try await local.unassign(vendor, from: block)
        await coordinator.mirrorRemoteWrite(
            "delete", "block_vendors", id: block.id,
            detail: ["vendor": vendor.id.uuidString]
        ) {
            try await self.remote.unassign(vendor, from: block)
        }
    }
}

@MainActor
struct WriteThroughShiftRecordRepository: ShiftRecordRepositing {
    let local: any ShiftRecordRepositing
    let remote: any ShiftRecordRepositing
    let coordinator: WriteThroughCoordinator

    func insert(_ record: ShiftRecord, into event: EventModel) async throws {
        try await local.insert(record, into: event)
        await coordinator.mirrorRemoteWrite("insert", "shift_records", id: record.id) {
            try await self.remote.insert(record, into: event)
        }
    }

    func fetch(id: UUID) async throws -> ShiftRecord? {
        try await local.fetch(id: id)
    }

    func fetchAll(for event: EventModel) async throws -> [ShiftRecord] {
        try await local.fetchAll(for: event)
    }

    func delete(_ record: ShiftRecord) async throws {
        try await local.delete(record)
        await coordinator.mirrorRemoteWrite("delete", "shift_records", id: record.id) {
            try await self.remote.delete(record)
        }
    }

    func save() async throws {
        try await coordinator.save()
    }
}
