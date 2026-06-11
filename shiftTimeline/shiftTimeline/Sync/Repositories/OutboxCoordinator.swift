import Foundation
import Models
import Services
import SwiftData

/// The kind of mutation an ``OutboxEntry`` represents. Persisted as the entry's
/// `operation` string; this typed wrapper keeps enqueue call sites honest.
enum OutboxOperation: String {
    case insert
    case update
    case delete
}

/// Appends an ``OutboxEntry`` to the local write queue for every repository
/// mutation, so the offline ``SyncEngine`` flush can replay them to
/// Supabase FIFO once connectivity returns.
///
/// This is the offline analogue of `WriteThroughCoordinator`: where the
/// write-through layer mirrored each write to Supabase *inline*, this layer
/// records a durable, self-contained entry (table + row id + op + a DTO-encoded
/// payload snapshot) and returns immediately. The local SwiftData write has
/// already happened (local-first); the network is never on the user's path.
///
/// **Ordering / causality.** Each entry is stamped with a monotonic, gap-free
/// ``OutboxEntry/sequence`` assigned here in enqueue order. Because the app
/// inserts an aggregate in foreign-key order (event → track → block; event →
/// vendor; assignment only after both endpoints exist), enqueue order *is*
/// causal order, so flushing by ascending `sequence` always sends a parent
/// before its children. The `save()` path additionally sorts the dirty set
/// parents-first before stamping, so bypass-inserts (e.g. `recordShift`) and
/// in-place edits converge to the same rule.
///
/// **Payloads.** `insert`/`update` entries carry the row's DTO encoded as JSON
/// (the same shape the remote repositories upsert); `delete` entries on the main
/// tables carry no payload (the row id is enough). Junction entries always carry
/// their composite-key DTO — including deletes — because the row id alone can't
/// identify the pair.
///
/// **Known/accepted:** an explicit `insert` followed by a `save()` in the same
/// cycle enqueues both an `insert` and an `update` for that row. The flush is an
/// idempotent upsert, so this is correctness-safe; coalescing is a flush-time
/// optimization.
@MainActor
final class OutboxCoordinator {
    private let context: ModelContext
    private let currentOwnerID: @MainActor () -> UUID?
    private let diagnostics: SyncDiagnosticsCenter
    /// Called after every enqueue so the SyncEngine can schedule a (debounced)
    /// flush — this is what makes a local write reach Supabase within seconds
    /// instead of only on the next launch / sign-in / foreground / reconnect.
    /// Defaults to a no-op so the local-only and test paths don't need it.
    private let onEnqueue: @MainActor () -> Void
    private let encoder = JSONEncoder()

    /// In-memory high-water mark, seeded lazily from the store's max on first
    /// use, then incremented per enqueue. Keeps `sequence` strictly increasing
    /// within a session regardless of when the context is saved; a fresh
    /// coordinator after relaunch re-seeds from the max surviving (unflushed)
    /// entry, which is all that ordering among pending writes requires.
    private var lastSequence: Int?

    init(
        context: ModelContext,
        currentOwnerID: @escaping @MainActor () -> UUID?,
        diagnostics: SyncDiagnosticsCenter = .shared,
        onEnqueue: @escaping @MainActor () -> Void = {}
    ) {
        self.context = context
        self.currentOwnerID = currentOwnerID
        self.diagnostics = diagnostics
        self.onEnqueue = onEnqueue
    }

    // MARK: - Enqueue (explicit repository ops)

    /// Enqueues an entry for a top-level aggregate write. No-op for model types
    /// that aren't synced (e.g. `OutboxEntry` itself), so it's safe to feed the
    /// raw dirty set through it.
    func enqueueWrite(_ op: OutboxOperation, _ model: any PersistentModel) {
        guard let (table, rowID) = Self.identity(of: model) else { return }
        let payload = (op == .delete) ? nil : buildPayload(for: model)
        enqueue(op: op, table: table, rowID: rowID, payload: payload)
    }

    /// Enqueues a `block_vendors` junction change. The DTO (carrying the
    /// composite key) is the payload for both insert and delete.
    func enqueueAssignment(_ op: OutboxOperation, vendor: VendorModel, block: TimeBlockModel) {
        let payload: Data?
        if let eventID = block.track?.event?.id {
            payload = encode(
                BlockVendorDTO(blockID: block.id, eventVendorID: vendor.id, eventID: eventID),
                table: "block_vendors", id: block.id
            )
        } else {
            logPayloadUnavailable(table: "block_vendors", id: block.id, reason: "missingEvent")
            payload = nil
        }
        enqueue(op: op, table: "block_vendors", rowID: block.id, payload: payload)
    }

    /// Enqueues a `block_dependencies` junction change (`block` depends on
    /// `dependency`). The DTO is the payload for both insert and delete.
    func enqueueDependency(_ op: OutboxOperation, block: TimeBlockModel, dependsOn dependency: TimeBlockModel) {
        let payload: Data?
        if let eventID = block.track?.event?.id {
            payload = encode(
                BlockDependencyDTO(blockID: block.id, dependsOnBlockID: dependency.id, eventID: eventID),
                table: "block_dependencies", id: block.id
            )
        } else {
            logPayloadUnavailable(table: "block_dependencies", id: block.id, reason: "missingEvent")
            payload = nil
        }
        enqueue(op: op, table: "block_dependencies", rowID: block.id, payload: payload)
    }

    // MARK: - Save (edits + bypass-inserts)

    /// Flushes pending local changes, enqueuing an entry for every dirty
    /// aggregate first. Catches rows inserted straight into the context
    /// (`recordShift`, tagged `insert`) and in-place edits (`EditEventSheet`,
    /// tagged `update`) that never went through an explicit repository op. The
    /// dirty set is snapshotted and sorted parents-first before stamping so
    /// sequences preserve causality.
    func save() throws {
        let dirty =
            context.insertedModelsArray.map { (model: $0, op: OutboxOperation.insert) }
            + context.changedModelsArray.map { (model: $0, op: OutboxOperation.update) }
        for item in dirty.sorted(by: { Self.rank($0.model) < Self.rank($1.model) }) {
            enqueueWrite(item.op, item.model)
        }
        try context.save()
    }

    // MARK: - Core

    private func enqueue(op: OutboxOperation, table: String, rowID: UUID, payload: Data?) {
        let entry = OutboxEntry(
            sequence: nextSequence(),
            tableName: table,
            rowID: rowID,
            operation: op.rawValue,
            payload: payload
        )
        context.insert(entry)
        // Nudge a debounced flush; a burst (event → track → blocks) collapses into
        // one flush via the scheduler's window.
        onEnqueue()
    }

    private func nextSequence() -> Int {
        let base: Int
        if let last = lastSequence {
            base = last
        } else {
            var descriptor = FetchDescriptor<OutboxEntry>(
                sortBy: [SortDescriptor(\.sequence, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            base = (try? context.fetch(descriptor))?.first?.sequence ?? 0
        }
        let next = base + 1
        lastSequence = next
        return next
    }

    // MARK: - Payloads

    private func buildPayload(for model: any PersistentModel) -> Data? {
        switch model {
        case let event as EventModel:
            guard let ownerID = currentOwnerID() else {
                logPayloadUnavailable(table: "events", id: event.id, reason: "ownerUnavailable")
                return nil
            }
            return encode(event.toDTO(ownerID: ownerID), table: "events", id: event.id)
        case let track as TimelineTrack:
            guard let eventID = track.event?.id else {
                logPayloadUnavailable(table: "tracks", id: track.id, reason: "missingEvent")
                return nil
            }
            return encode(track.toDTO(eventID: eventID), table: "tracks", id: track.id)
        case let block as TimeBlockModel:
            guard let track = block.track, let eventID = track.event?.id else {
                logPayloadUnavailable(table: "blocks", id: block.id, reason: "missingParent")
                return nil
            }
            return encode(block.toDTO(trackID: track.id, eventID: eventID), table: "blocks", id: block.id)
        case let vendor as VendorModel:
            guard let eventID = vendor.event?.id else {
                logPayloadUnavailable(table: "event_vendors", id: vendor.id, reason: "missingEvent")
                return nil
            }
            return encode(vendor.toDTO(eventID: eventID), table: "event_vendors", id: vendor.id)
        case let shift as ShiftRecord:
            guard let eventID = shift.event?.id else {
                logPayloadUnavailable(table: "shift_records", id: shift.id, reason: "missingEvent")
                return nil
            }
            return encode(
                shift.toDTO(eventID: eventID, sourceBlockID: shift.sourceBlock?.id),
                table: "shift_records", id: shift.id
            )
        default:
            return nil
        }
    }

    private func encode(_ dto: some Encodable, table: String, id: UUID) -> Data? {
        do {
            return try encoder.encode(dto)
        } catch {
            diagnostics.record(
                .push, "enqueueEncodeFailed",
                params: ["table": table, "id": id.uuidString, "error": String(describing: error)],
                severity: .error
            )
            return nil
        }
    }

    private func logPayloadUnavailable(table: String, id: UUID, reason: String) {
        diagnostics.record(
            .push, "enqueuePayloadUnavailable",
            params: ["table": table, "id": id.uuidString, "reason": reason],
            severity: .warning
        )
    }

    // MARK: - Type mapping

    /// The Supabase table + row id for a synced model, or `nil` for local-only
    /// types (so the dirty set can be filtered through it safely).
    private static func identity(of model: any PersistentModel) -> (table: String, rowID: UUID)? {
        switch model {
        case let event as EventModel: return ("events", event.id)
        case let track as TimelineTrack: return ("tracks", track.id)
        case let block as TimeBlockModel: return ("blocks", block.id)
        case let vendor as VendorModel: return ("event_vendors", vendor.id)
        case let shift as ShiftRecord: return ("shift_records", shift.id)
        default: return nil
        }
    }

    /// Foreign-key depth, used to sort the dirty set parents-before-children.
    private static func rank(_ model: any PersistentModel) -> Int {
        if model is EventModel { return 0 }
        if model is TimelineTrack { return 1 }
        if model is TimeBlockModel { return 2 }
        if model is VendorModel { return 3 }
        if model is ShiftRecord { return 4 }
        return 5
    }
}
