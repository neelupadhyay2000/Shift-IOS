import Foundation
import Models
import Services
import SwiftData

/// Reconstructs the local SwiftData cache from Supabase on login/launch and
/// pull-to-refresh.
///
/// `hydrate()` fetches the accessible graph off the main actor (the source is
/// `nonisolated`) and hands it to a ``SnapshotApplying`` importer. In production
/// that importer is a `@ModelActor` running the bulk fetch/insert/wire/save on a
/// **background** context, so a full hydrate never blocks the main thread — which
/// is what kept pull-to-refresh from freezing the UI while the graph rebuilt.
///
/// Upsert-only — rows deleted on the server (tombstones) and local-only rows are
/// left untouched here; that reconciliation belongs to the Outbox/delta sync.
@MainActor
struct InitialHydrator {
    private let source: any HydrationSource
    private let applier: any SnapshotApplying
    private let diagnostics: SyncDiagnosticsCenter

    init(
        source: any HydrationSource,
        applier: any SnapshotApplying,
        diagnostics: SyncDiagnosticsCenter = .shared
    ) {
        self.source = source
        self.applier = applier
        self.diagnostics = diagnostics
    }

    /// Fetches the accessible graph and merges it into the local store. Both the
    /// fetch and the merge run off the main actor.
    func hydrate() async throws {
        let snapshot: HydrationSnapshot
        do {
            snapshot = try await source.fetchSnapshot()
        } catch {
            diagnostics.record(
                .fetch, "hydrationFetchFailed",
                params: ["error": String(describing: error)],
                severity: .error
            )
            throw error
        }

        do {
            try await applier.apply(snapshot)
        } catch {
            diagnostics.record(
                .fetch, "hydrationApplyFailed",
                params: ["error": String(describing: error)],
                severity: .error
            )
            throw error
        }

        diagnostics.record(
            .fetch, "hydrated",
            params: [
                "events": String(snapshot.events.count),
                "blocks": String(snapshot.blocks.count),
                "vendors": String(snapshot.vendors.count),
            ]
        )
    }
}

// MARK: - Applier

/// Merges a fetched ``HydrationSnapshot`` into SwiftData. Abstracted so the
/// production background importer and a test double share one entry point.
protocol SnapshotApplying: Sendable {
    func apply(_ snapshot: HydrationSnapshot) async throws
}

/// Production importer. `@ModelActor` binds it to its own `ModelContext` on a
/// background executor, so the upsert/wire/save runs off the main thread; the
/// main context's `@Query` picks up the merged changes after save (the standard
/// SwiftData background-import pattern).
@ModelActor
actor BackgroundSnapshotApplier: SnapshotApplying {
    func apply(_ snapshot: HydrationSnapshot) throws {
        try SnapshotMerger(context: modelContext).apply(snapshot)
    }
}

/// The pure merge: upsert scalars by id (skipping tombstones), wire relationships
/// by id, save. Nonisolated and context-injected so it runs on whatever executor
/// calls it — the background applier in production, an in-memory context in tests.
/// Idempotent: re-running updates existing rows in place rather than duplicating.
struct SnapshotMerger {
    let context: ModelContext

    /// Merges a snapshot into SwiftData: upsert scalars by id, wire relationships, save.
    func apply(_ snapshot: HydrationSnapshot) throws {
        let eventsByID = try upsertEvents(snapshot.events)
        let tracksByID = try upsertTracks(snapshot.tracks)
        let blocksByID = try upsertBlocks(snapshot.blocks)
        let vendorsByID = try upsertVendors(snapshot.vendors)
        let recordsByID = try upsertShiftRecords(snapshot.shiftRecords)

        wireRelationships(
            snapshot,
            eventsByID: eventsByID,
            tracksByID: tracksByID,
            blocksByID: blocksByID,
            vendorsByID: vendorsByID,
            recordsByID: recordsByID
        )

        try context.save()
    }

    // MARK: - Upsert (find-or-create + apply scalars)

    private func upsertEvents(_ dtos: [EventDTO]) throws -> [UUID: EventModel] {
        let existing = try context.fetch(FetchDescriptor<EventModel>())
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for dto in dtos {
            // Defense-in-depth: the source already filters tombstones, but never
            // resurrect a soft-deleted row if one slips into the snapshot — the
            // merge is upsert-only and would otherwise re-create it locally.
            guard dto.deletedAt == nil else { continue }
            if let model = byID[dto.id] {
                dto.apply(to: model)
            } else {
                let model = dto.makeModel()
                context.insert(model)
                byID[dto.id] = model
            }
        }
        return byID
    }

    private func upsertTracks(_ dtos: [TrackDTO]) throws -> [UUID: TimelineTrack] {
        let existing = try context.fetch(FetchDescriptor<TimelineTrack>())
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for dto in dtos {
            guard dto.deletedAt == nil else { continue }   // never resurrect a tombstone
            if let model = byID[dto.id] {
                dto.apply(to: model)
            } else {
                let model = dto.makeModel()
                context.insert(model)
                byID[dto.id] = model
            }
        }
        return byID
    }

    private func upsertBlocks(_ dtos: [BlockDTO]) throws -> [UUID: TimeBlockModel] {
        let existing = try context.fetch(FetchDescriptor<TimeBlockModel>())
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for dto in dtos {
            guard dto.deletedAt == nil else { continue }   // never resurrect a tombstone
            if let model = byID[dto.id] {
                dto.apply(to: model)
            } else {
                let model = dto.makeModel()
                context.insert(model)
                byID[dto.id] = model
            }
        }
        return byID
    }

    private func upsertVendors(_ dtos: [EventVendorDTO]) throws -> [UUID: VendorModel] {
        let existing = try context.fetch(FetchDescriptor<VendorModel>())
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for dto in dtos {
            guard dto.deletedAt == nil else { continue }   // never resurrect a tombstone
            if let model = byID[dto.id] {
                dto.apply(to: model)
            } else {
                let model = dto.makeModel()
                context.insert(model)
                byID[dto.id] = model
            }
        }
        return byID
    }

    private func upsertShiftRecords(_ dtos: [ShiftRecordDTO]) throws -> [UUID: ShiftRecord] {
        let existing = try context.fetch(FetchDescriptor<ShiftRecord>())
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for dto in dtos {
            guard dto.deletedAt == nil else { continue }   // never resurrect a tombstone
            if let model = byID[dto.id] {
                dto.apply(to: model)
            } else {
                let model = dto.makeModel()
                context.insert(model)
                byID[dto.id] = model
            }
        }
        return byID
    }

    // MARK: - Relationship wiring (by id)

    private func wireRelationships(
        _ snapshot: HydrationSnapshot,
        eventsByID: [UUID: EventModel],
        tracksByID: [UUID: TimelineTrack],
        blocksByID: [UUID: TimeBlockModel],
        vendorsByID: [UUID: VendorModel],
        recordsByID: [UUID: ShiftRecord]
    ) {
        for dto in snapshot.tracks {
            guard let model = tracksByID[dto.id] else { continue }
            dto.linkRelationships(model, events: eventsByID)
        }
        for dto in snapshot.blocks {
            guard let model = blocksByID[dto.id] else { continue }
            dto.linkParent(model, tracks: tracksByID)
        }
        for dto in snapshot.vendors {
            guard let model = vendorsByID[dto.id] else { continue }
            dto.linkRelationships(model, events: eventsByID)
        }

        // Junctions: group once by block, then wire only the fetched blocks so a
        // server's assignment set replaces that block's relationships authoritatively.
        let vendorJunctions = Dictionary(grouping: snapshot.blockVendors, by: \.blockID)
        let dependencyJunctions = Dictionary(grouping: snapshot.blockDependencies, by: \.blockID)
        for dto in snapshot.blocks {
            guard let model = blocksByID[dto.id] else { continue }
            model.linkVendors(vendorJunctions[dto.id] ?? [], vendors: vendorsByID)
            model.linkDependencies(dependencyJunctions[dto.id] ?? [], blocks: blocksByID)
        }

        for dto in snapshot.shiftRecords {
            guard let model = recordsByID[dto.id] else { continue }
            dto.linkRelationships(model, events: eventsByID, blocks: blocksByID)
        }
    }
}
