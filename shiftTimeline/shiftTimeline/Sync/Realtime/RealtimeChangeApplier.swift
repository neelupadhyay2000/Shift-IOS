import Foundation
import Models
import Services
import SwiftData
import Supabase

/// Applies realtime row changes to the local SwiftData store on the main actor,
/// so `@Query`-driven views update live.
///
/// INSERT/UPDATE → **upsert by id** (find-or-create, apply scalars, wire the
/// parent relationship); DELETE → remove the local row. A row whose decoded DTO
/// carries `deleted_at` is treated as a delete (soft-delete tombstone arriving
/// as an UPDATE). Junction tables apply as incremental add/remove rather than a
/// row upsert. Each change is saved immediately so the UI reflects it at once.
@MainActor
struct RealtimeChangeApplier {
    private let context: ModelContext
    private let decoder: JSONDecoder
    private let diagnostics: SyncDiagnosticsCenter
    private let echoSuppressor: RealtimeEchoSuppressor?

    /// Tables with a single `id` primary key, for which a self-write echo can be
    /// recognized by id. Junctions apply incrementally (idempotent) and aren't
    /// suppressed.
    private static let suppressibleTables: Set<String> = [
        "events", "tracks", "blocks", "event_vendors", "shift_records",
    ]

    init(
        context: ModelContext,
        decoder: JSONDecoder = JSONDecoder(),
        diagnostics: SyncDiagnosticsCenter = .shared,
        echoSuppressor: RealtimeEchoSuppressor? = nil
    ) {
        self.context = context
        self.decoder = decoder
        self.diagnostics = diagnostics
        self.echoSuppressor = echoSuppressor
    }

    /// Consumes the realtime stream, applying each change on the main actor.
    /// A failed row is recorded to diagnostics and skipped so it doesn't stall
    /// the stream.
    func apply(_ changes: AsyncStream<RealtimeChange>) async {
        for await change in changes {
            do {
                try apply(change)
            } catch {
                diagnostics.record(
                    .applyRemote, "realtimeApplyFailed",
                    params: ["table": change.table, "error": String(describing: error)],
                    severity: .error
                )
            }
        }
    }

    /// Applies a single change and saves. A change that is this device's own
    /// echo is skipped so it never re-applies over (or clobbers) local state.
    func apply(_ change: RealtimeChange) throws {
        if isSelfEcho(change) { return }
        switch change {
        case let .upsert(table, record):
            try applyUpsert(table: table, record: record)
        case let .delete(table, oldRecord):
            try applyDelete(table: table, oldRecord: oldRecord)
        }
        try context.save()
    }

    private func isSelfEcho(_ change: RealtimeChange) -> Bool {
        guard let echoSuppressor else { return false }
        let table = change.table
        guard Self.suppressibleTables.contains(table) else { return false }
        let payload: JSONObject
        switch change {
        case let .upsert(_, record): payload = record
        case let .delete(_, oldRecord): payload = oldRecord
        }
        guard let id = uuid(payload, "id") else { return false }
        return echoSuppressor.shouldSuppress(table: table, id: id)
    }

    // MARK: - Upsert (insert / update)

    private func applyUpsert(table: String, record: JSONObject) throws {
        switch table {
        case "events":
            let dto = try decode(EventDTO.self, record)
            if dto.deletedAt != nil { try softDeleteEvent(dto) } else { try upsertEvent(dto) }
        case "tracks":
            let dto = try decode(TrackDTO.self, record)
            if dto.deletedAt != nil { try softDeleteTrack(dto) } else { try upsertTrack(dto) }
        case "blocks":
            let dto = try decode(BlockDTO.self, record)
            if dto.deletedAt != nil { try softDeleteBlock(dto) } else { try upsertBlock(dto) }
        case "event_vendors":
            let dto = try decode(EventVendorDTO.self, record)
            if dto.deletedAt != nil { try softDeleteVendor(dto) } else { try upsertVendor(dto) }
        case "shift_records":
            let dto = try decode(ShiftRecordDTO.self, record)
            if dto.deletedAt != nil { try deleteShiftRecord(id: dto.id) } else { try upsertShiftRecord(dto) }
        case "block_vendors":
            let dto = try decode(BlockVendorDTO.self, record)
            if dto.deletedAt != nil {
                try unassign(blockID: dto.blockID, vendorID: dto.eventVendorID)
            } else {
                try assign(blockID: dto.blockID, vendorID: dto.eventVendorID)
            }
        case "block_dependencies":
            let dto = try decode(BlockDependencyDTO.self, record)
            if dto.deletedAt != nil {
                try removeDependency(blockID: dto.blockID, dependsOnID: dto.dependsOnBlockID)
            } else {
                try addDependency(blockID: dto.blockID, dependsOnID: dto.dependsOnBlockID)
            }
        default:
            break
        }
    }

    private func upsertEvent(_ dto: EventDTO) throws {
        let existing = try existingEvent(id: dto.id)
        if let existing, !shouldApply(incoming: dto.updatedAt?.value, onto: existing.updatedAt) { return }
        let model = existing ?? insert(dto.makeModel())
        dto.apply(to: model)
    }

    private func upsertTrack(_ dto: TrackDTO) throws {
        let existing = try existingTrack(id: dto.id)
        if let existing, !shouldApply(incoming: dto.updatedAt?.value, onto: existing.updatedAt) { return }
        let model = existing ?? insert(dto.makeModel())
        dto.apply(to: model)
        if let event = try existingEvent(id: dto.eventID) {
            dto.linkRelationships(model, events: [event.id: event])
        }
    }

    private func upsertBlock(_ dto: BlockDTO) throws {
        let existing = try existingBlock(id: dto.id)
        if let existing, !shouldApply(incoming: dto.updatedAt?.value, onto: existing.updatedAt) { return }
        let model = existing ?? insert(dto.makeModel())
        dto.apply(to: model)
        if let track = try existingTrack(id: dto.trackID) {
            dto.linkParent(model, tracks: [track.id: track])
        }
    }

    private func upsertVendor(_ dto: EventVendorDTO) throws {
        // Vendor ack (and the rest of the row) is last-write-wins by server
        // `updated_at` (SHIFT-616): a stale version — e.g. a vendor's own ack
        // arriving after the planner's newer reset — is skipped rather than
        // clobbering the current state, so ack and edits never ping-pong.
        let existing = try existingVendor(id: dto.id)
        if let existing, !shouldApply(incoming: dto.updatedAt?.value, onto: existing.updatedAt) { return }
        let model = existing ?? insert(dto.makeModel())
        dto.apply(to: model)
        if let event = try existingEvent(id: dto.eventID) {
            dto.linkRelationships(model, events: [event.id: event])
        }
    }

    private func upsertShiftRecord(_ dto: ShiftRecordDTO) throws {
        let model = try existingShiftRecord(id: dto.id) ?? insert(dto.makeModel())
        dto.apply(to: model)
        var events: [UUID: EventModel] = [:]
        if let event = try existingEvent(id: dto.eventID) { events[event.id] = event }
        var blocks: [UUID: TimeBlockModel] = [:]
        if let sourceID = dto.sourceBlockID, let block = try existingBlock(id: sourceID) {
            blocks[block.id] = block
        }
        dto.linkRelationships(model, events: events, blocks: blocks)
    }

    /// Last-write-wins (SHIFT-605): apply a remote row only when it isn't older
    /// than the local version. `incoming`/`current` are server `updated_at`s; a
    /// `nil` on either side (no known server time) applies — there's no basis to
    /// call it stale. Equal versions are skipped so a re-delivery or self-echo
    /// can't clobber a local edit made on top of that same version. Combined with
    /// the planner-authoritative rule (only the owner can write timeline data,
    /// enforced by RLS), this converges the owner's own devices on the newest
    /// server write regardless of arrival order.
    private func shouldApply(incoming: Date?, onto current: Date?) -> Bool {
        guard let incoming, let current else { return true }
        return incoming > current
    }

    // MARK: - Soft-delete (tombstone)

    // A soft-delete arrives as an upsert whose DTO carries `deleted_at` (SHIFT-618).
    // The local row is removed, but only under the same LWW rule as an edit: a
    // tombstone older than the local version is skipped, so a stale delete can't
    // wipe a newer edit. The row stays a tombstone on the server until purged, so
    // a device that was offline still learns of the deletion via the delta.

    private func softDeleteEvent(_ dto: EventDTO) throws {
        guard let existing = try existingEvent(id: dto.id),
              shouldApply(incoming: dto.updatedAt?.value, onto: existing.updatedAt) else { return }
        context.delete(existing)
    }

    private func softDeleteTrack(_ dto: TrackDTO) throws {
        guard let existing = try existingTrack(id: dto.id),
              shouldApply(incoming: dto.updatedAt?.value, onto: existing.updatedAt) else { return }
        context.delete(existing)
    }

    private func softDeleteBlock(_ dto: BlockDTO) throws {
        guard let existing = try existingBlock(id: dto.id),
              shouldApply(incoming: dto.updatedAt?.value, onto: existing.updatedAt) else { return }
        context.delete(existing)
    }

    private func softDeleteVendor(_ dto: EventVendorDTO) throws {
        guard let existing = try existingVendor(id: dto.id),
              shouldApply(incoming: dto.updatedAt?.value, onto: existing.updatedAt) else { return }
        context.delete(existing)
    }

    // MARK: - Delete

    private func applyDelete(table: String, oldRecord: JSONObject) throws {
        switch table {
        case "events":
            if let id = uuid(oldRecord, "id") { try deleteEvent(id: id) }
        case "tracks":
            if let id = uuid(oldRecord, "id") { try deleteTrack(id: id) }
        case "blocks":
            if let id = uuid(oldRecord, "id") { try deleteBlock(id: id) }
        case "event_vendors":
            if let id = uuid(oldRecord, "id") { try deleteVendor(id: id) }
        case "shift_records":
            if let id = uuid(oldRecord, "id") { try deleteShiftRecord(id: id) }
        case "block_vendors":
            if let block = uuid(oldRecord, "block_id"), let vendor = uuid(oldRecord, "event_vendor_id") {
                try unassign(blockID: block, vendorID: vendor)
            }
        case "block_dependencies":
            if let block = uuid(oldRecord, "block_id"), let dependsOn = uuid(oldRecord, "depends_on_block_id") {
                try removeDependency(blockID: block, dependsOnID: dependsOn)
            }
        default:
            break
        }
    }

    private func deleteEvent(id: UUID) throws {
        if let model = try existingEvent(id: id) { context.delete(model) }
    }

    private func deleteTrack(id: UUID) throws {
        if let model = try existingTrack(id: id) { context.delete(model) }
    }

    private func deleteBlock(id: UUID) throws {
        if let model = try existingBlock(id: id) { context.delete(model) }
    }

    private func deleteVendor(id: UUID) throws {
        if let model = try existingVendor(id: id) { context.delete(model) }
    }

    private func deleteShiftRecord(id: UUID) throws {
        if let model = try existingShiftRecord(id: id) { context.delete(model) }
    }

    // MARK: - Junction relationships

    private func assign(blockID: UUID, vendorID: UUID) throws {
        guard let block = try existingBlock(id: blockID),
              let vendor = try existingVendor(id: vendorID) else { return }
        var vendors = block.vendors ?? []
        guard !vendors.contains(where: { $0.id == vendorID }) else { return }
        vendors.append(vendor)
        block.vendors = vendors
    }

    private func unassign(blockID: UUID, vendorID: UUID) throws {
        guard let block = try existingBlock(id: blockID) else { return }
        block.vendors?.removeAll { $0.id == vendorID }
    }

    private func addDependency(blockID: UUID, dependsOnID: UUID) throws {
        guard let block = try existingBlock(id: blockID),
              let dependency = try existingBlock(id: dependsOnID) else { return }
        var dependencies = block.dependencies ?? []
        guard !dependencies.contains(where: { $0.id == dependsOnID }) else { return }
        dependencies.append(dependency)
        block.dependencies = dependencies
    }

    private func removeDependency(blockID: UUID, dependsOnID: UUID) throws {
        guard let block = try existingBlock(id: blockID) else { return }
        block.dependencies?.removeAll { $0.id == dependsOnID }
    }

    // MARK: - Lookups & helpers

    private func decode<Row: Decodable>(_ type: Row.Type, _ record: JSONObject) throws -> Row {
        try record.decode(as: Row.self, decoder: decoder)
    }

    private func uuid(_ record: JSONObject, _ key: String) -> UUID? {
        record[key]?.stringValue.flatMap(UUID.init(uuidString:))
    }

    @discardableResult
    private func insert<Model: PersistentModel>(_ model: Model) -> Model {
        context.insert(model)
        return model
    }

    private func existingEvent(id: UUID) throws -> EventModel? {
        var descriptor = FetchDescriptor<EventModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func existingTrack(id: UUID) throws -> TimelineTrack? {
        var descriptor = FetchDescriptor<TimelineTrack>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func existingBlock(id: UUID) throws -> TimeBlockModel? {
        var descriptor = FetchDescriptor<TimeBlockModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func existingVendor(id: UUID) throws -> VendorModel? {
        var descriptor = FetchDescriptor<VendorModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func existingShiftRecord(id: UUID) throws -> ShiftRecord? {
        var descriptor = FetchDescriptor<ShiftRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
