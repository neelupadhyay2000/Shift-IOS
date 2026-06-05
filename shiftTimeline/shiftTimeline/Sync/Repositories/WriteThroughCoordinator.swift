import Foundation
import Models
import Services
import SwiftData

/// Drives the remote half of a write-through `save()`.
///
/// Explicit repository ops (`insert`/`delete`/assignment) already mirror to
/// Supabase inline, so `save()` exists to flush the **local** context and catch
/// the two mutation paths that don't go through an explicit remote call:
/// in-place edits (e.g. `EditEventSheet` mutates the model then calls `save()`)
/// and rows inserted straight into the context (e.g. `recordShift`).
///
/// Local-first: the context is saved first, then each dirty row is upserted
/// remotely by id. Re-upserting a row an explicit `insert(...)` already wrote is
/// harmless (idempotent). Robust, ordered change capture — and offline queueing —
/// arrive with the E13 Outbox; this is the online-only bridge.
@MainActor
final class WriteThroughCoordinator {
    private let context: ModelContext
    private let remote: any RepositoryProviding

    init(context: ModelContext, remote: any RepositoryProviding) {
        self.context = context
        self.remote = remote
    }

    /// Flushes pending local changes, then mirrors the just-saved rows to remote.
    func save() async throws {
        // Snapshot the dirty set synchronously — before any suspension — so an
        // autosave tick can't clear it out from under us.
        let dirty = context.insertedModelsArray + context.changedModelsArray
        try context.save()
        try await mirror(dirty)
    }

    /// Upserts each dirty model to its remote table, parents before children so
    /// denormalized foreign keys always resolve.
    private func mirror(_ models: [any PersistentModel]) async throws {
        let ordered = models.sorted { Self.tableRank($0) < Self.tableRank($1) }
        for model in ordered {
            switch model {
            case let event as EventModel:
                try await remote.events.insert(event)
            case let track as TimelineTrack:
                if let event = track.event { try await remote.tracks.insert(track, into: event) }
            case let block as TimeBlockModel:
                if let track = block.track { try await remote.blocks.insert(block, into: track) }
            case let vendor as VendorModel:
                if let event = vendor.event { try await remote.vendors.insert(vendor, into: event) }
            case let record as ShiftRecord:
                if let event = record.event { try await remote.shiftRecords.insert(record, into: event) }
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
