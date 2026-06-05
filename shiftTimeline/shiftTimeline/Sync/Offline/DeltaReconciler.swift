import Foundation
import Services
import Supabase

/// Catches a device up on changes it missed while backgrounded — when realtime
/// wasn't connected. On launch/foreground it pulls every row changed since the
/// scope's watermark, merges it into SwiftData, then advances the watermark.
///
/// A delta is exactly "the realtime changes I missed", so it reuses
/// ``RealtimeChangeApplier``: each fetched row is replayed as an upsert (a row
/// carrying `deleted_at` becomes a local delete; junctions apply incrementally),
/// parents before children. Idempotent — rows already present are upserted by id
/// with no duplication — so it's safe to run on every foreground.
@MainActor
struct DeltaReconciler {
    private let source: any DeltaSource
    private let applier: RealtimeChangeApplier
    private let watermarks: LastPulledStore
    private let diagnostics: SyncDiagnosticsCenter

    init(
        source: any DeltaSource,
        applier: RealtimeChangeApplier,
        watermarks: LastPulledStore,
        diagnostics: SyncDiagnosticsCenter = .shared
    ) {
        self.source = source
        self.applier = applier
        self.watermarks = watermarks
        self.diagnostics = diagnostics
    }

    /// Pulls and merges the delta for `scope`, advancing its watermark on success.
    func reconcile(scope: SyncScope = .account) async throws {
        let since = watermarks.lastPulled(for: scope)

        let snapshot: HydrationSnapshot
        do {
            snapshot = try await source.fetchDelta(since: since)
        } catch {
            diagnostics.record(
                .fetch, "deltaFetchFailed",
                params: ["error": String(describing: error)], severity: .error
            )
            throw error
        }

        apply(snapshot)

        // Advance only when the delta carried rows; an empty delta leaves the
        // watermark where it is so the next pull re-queries the same window.
        if let highWater = Self.highWaterMark(snapshot) {
            watermarks.recordPull(at: highWater, for: scope)
        }

        diagnostics.record(.fetch, "deltaReconciled", params: [
            "events": String(snapshot.events.count),
            "blocks": String(snapshot.blocks.count),
            "vendors": String(snapshot.vendors.count),
        ])
    }

    /// Replays each changed row through the realtime applier, parents before
    /// children. A row that fails is recorded and skipped so it can't stall the
    /// rest of the catch-up.
    private func apply(_ snapshot: HydrationSnapshot) {
        for change in changes(from: snapshot) {
            do {
                try applier.apply(change)
            } catch {
                diagnostics.record(
                    .applyRemote, "deltaApplyFailed",
                    params: ["table": change.table, "error": String(describing: error)], severity: .error
                )
            }
        }
    }

    private func changes(from snapshot: HydrationSnapshot) -> [RealtimeChange] {
        snapshot.events.compactMap { change("events", $0) }
            + snapshot.tracks.compactMap { change("tracks", $0) }
            + snapshot.blocks.compactMap { change("blocks", $0) }
            + snapshot.vendors.compactMap { change("event_vendors", $0) }
            + snapshot.blockVendors.compactMap { change("block_vendors", $0) }
            + snapshot.blockDependencies.compactMap { change("block_dependencies", $0) }
            + snapshot.shiftRecords.compactMap { change("shift_records", $0) }
    }

    /// Encodes a fetched DTO back into the wire `JSONObject` the applier decodes —
    /// so the delta path and the realtime path share one apply implementation.
    private func change(_ table: String, _ dto: some Codable) -> RealtimeChange? {
        guard let record = try? JSONObject(dto) else {
            diagnostics.record(.applyRemote, "deltaEncodeFailed", params: ["table": table], severity: .error)
            return nil
        }
        return .upsert(table: table, record: record)
    }

    /// The newest server timestamp in the delta — the next watermark. Uses
    /// `updated_at` for main rows and `created_at`/`deleted_at` for junctions.
    static func highWaterMark(_ snapshot: HydrationSnapshot) -> Date? {
        var dates: [Date] = []
        dates += snapshot.events.compactMap { $0.updatedAt?.value }
        dates += snapshot.tracks.compactMap { $0.updatedAt?.value }
        dates += snapshot.blocks.compactMap { $0.updatedAt?.value }
        dates += snapshot.vendors.compactMap { $0.updatedAt?.value }
        dates += snapshot.shiftRecords.compactMap { $0.updatedAt?.value }
        dates += snapshot.blockVendors.compactMap { $0.createdAt?.value }
        dates += snapshot.blockVendors.compactMap { $0.deletedAt?.value }
        dates += snapshot.blockDependencies.compactMap { $0.createdAt?.value }
        dates += snapshot.blockDependencies.compactMap { $0.deletedAt?.value }
        return dates.max()
    }
}
