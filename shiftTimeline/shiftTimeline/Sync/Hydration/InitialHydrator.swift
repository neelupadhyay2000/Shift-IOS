import Foundation
import Models
import Services
import SwiftData

/// Reconstructs the local SwiftData cache from Supabase on login/launch.
///
/// Fetches every accessible row (RLS-scoped), upserts each into SwiftData **by
/// id** (find-or-create + apply scalars), then wires relationships by id using
/// the DTO mapping layer. Idempotent: re-running updates existing rows in place
/// rather than duplicating, so it's safe to call on every launch.
///
/// Upsert-only — rows deleted on the server (tombstones) and local-only rows are
/// left untouched here; that reconciliation belongs to the Outbox/delta sync.
@MainActor
struct InitialHydrator {
    private let source: any HydrationSource
    private let context: ModelContext
    private let diagnostics: SyncDiagnosticsCenter

    init(
        source: any HydrationSource,
        context: ModelContext,
        diagnostics: SyncDiagnosticsCenter = .shared
    ) {
        self.source = source
        self.context = context
        self.diagnostics = diagnostics
    }

    /// Fetches the accessible graph and merges it into the local store.
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

        try apply(snapshot)

        diagnostics.record(
            .fetch, "hydrated",
            params: [
                "events": String(snapshot.events.count),
                "blocks": String(snapshot.blocks.count),
                "vendors": String(snapshot.vendors.count),
            ]
        )
    }

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
