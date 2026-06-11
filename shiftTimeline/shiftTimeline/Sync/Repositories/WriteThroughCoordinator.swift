import Foundation
import Models
import Services
import SwiftData

/// Drives the remote half of write-through and keeps remote failures visible.
///
/// Explicit repository ops (`insert`/`delete`/assignment) mirror to Supabase
/// inline; `save()` flushes the **local** context and then mirrors the rows that
/// don't go through an explicit remote call — in-place edits (e.g.
/// `EditEventSheet`) and rows inserted straight into the context (e.g.
/// `recordShift`).
///
/// Every remote write is funnelled through ``mirrorRemoteWrite(_:_:id:detail:_:)``,
/// which is **local-first**: the local write has already succeeded, so a remote
/// failure is recorded to `SyncDiagnosticsCenter` (visible in the in-app
/// diagnostics screen and the unified log) rather than rethrown — it must not
/// fail the user's action, and must not be silently dropped. Ordered retry and
/// offline queueing arrive with the Outbox.
@MainActor
final class WriteThroughCoordinator {
    private let context: ModelContext
    private let remote: any RepositoryProviding
    private let diagnostics: SyncDiagnosticsCenter
    private let echoSuppressor: RealtimeEchoSuppressor?

    init(
        context: ModelContext,
        remote: any RepositoryProviding,
        diagnostics: SyncDiagnosticsCenter = .shared,
        echoSuppressor: RealtimeEchoSuppressor? = nil
    ) {
        self.context = context
        self.remote = remote
        self.diagnostics = diagnostics
        self.echoSuppressor = echoSuppressor
    }

    /// Runs a remote write, recording any failure to diagnostics instead of
    /// rethrowing. `op`/`table`/`id` identify the row for the diagnostic record.
    func mirrorRemoteWrite(
        _ op: String,
        _ table: String,
        id: UUID,
        detail: [String: String] = [:],
        _ work: () async throws -> Void
    ) async {
        do {
            try await work()
            // Remember the write so its realtime echo is recognized and skipped.
            echoSuppressor?.recordLocalWrite(table: table, id: id)
        } catch {
            var params = detail
            params["op"] = op
            params["table"] = table
            params["id"] = id.uuidString
            params["error"] = String(describing: error)
            diagnostics.record(.push, "remoteWriteFailed", params: params, severity: .error)
        }
    }

    /// Flushes pending local changes, then mirrors the just-saved rows to remote.
    /// Only the local `context.save()` can throw; remote failures are recorded.
    func save() async throws {
        // Snapshot the dirty set synchronously — before any suspension — so an
        // autosave tick can't clear it out from under us.
        let dirty = context.insertedModelsArray + context.changedModelsArray
        try context.save()
        await mirrorDirty(dirty)
    }

    /// Upserts each dirty model to its remote table, parents before children so
    /// denormalized foreign keys always resolve.
    private func mirrorDirty(_ models: [any PersistentModel]) async {
        let ordered = models.sorted { Self.tableRank($0) < Self.tableRank($1) }
        for model in ordered {
            switch model {
            case let event as EventModel:
                await mirrorRemoteWrite("upsert", "events", id: event.id) {
                    try await self.remote.events.insert(event)
                }
            case let track as TimelineTrack:
                if let event = track.event {
                    await mirrorRemoteWrite("upsert", "tracks", id: track.id) {
                        try await self.remote.tracks.insert(track, into: event)
                    }
                }
            case let block as TimeBlockModel:
                if let track = block.track {
                    await mirrorRemoteWrite("upsert", "blocks", id: block.id) {
                        try await self.remote.blocks.insert(block, into: track)
                    }
                }
            case let vendor as VendorModel:
                if let event = vendor.event {
                    await mirrorRemoteWrite("upsert", "event_vendors", id: vendor.id) {
                        try await self.remote.vendors.insert(vendor, into: event)
                    }
                }
            case let record as ShiftRecord:
                if let event = record.event {
                    await mirrorRemoteWrite("upsert", "shift_records", id: record.id) {
                        try await self.remote.shiftRecords.insert(record, into: event)
                    }
                }
            default:
                break // OutboxEntry and any other local-only model are not mirrored.
            }
        }
    }

    private static func tableRank(_ model: any PersistentModel) -> Int {
        if model is EventModel { return 0 }
        if model is TimelineTrack { return 1 }
        if model is TimeBlockModel { return 2 }
        if model is VendorModel { return 3 }
        if model is ShiftRecord { return 4 }
        return 5
    }
}
