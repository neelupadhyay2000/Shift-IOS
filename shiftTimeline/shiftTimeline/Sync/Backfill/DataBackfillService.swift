import Foundation
import Models
import Services
import SwiftData

/// One-time, post-migration upload of a CloudKit-era user's on-device data to
/// Supabase.
///
/// Walks the local SwiftData graph and enqueues an `insert` ``OutboxEntry`` for
/// every owned row, then saves. It does **not** touch the network: the existing
/// offline flush (``OutboxFlusher``) drains the queue FIFO when
/// connectivity returns. Enqueue is delegated to ``OutboxCoordinator`` so the
/// payloads, owner stamping, FK-ordered `sequence`, and junction encoding are
/// byte-for-byte identical to a normal repository write.
///
/// **Idempotency.** Every entry is keyed by the model's stable `id`, and the
/// flush upserts by id. Re-running the backfill (or a second device that shares
/// the same CloudKit-era ids) therefore converges on the same rows rather than
/// duplicating them. The run-once completion flag that makes this fire exactly
/// once per upgrade lives in ``BackfillCompletionStore``.
///
/// **Ownership.** Only events the signed-in user owns are uploaded: rows with no
/// owner yet (`ownerId == nil` — the CloudKit-era default) are claimed for the
/// current profile, and rows already owned by a *different* profile (a shared-in
/// event hydrated from another planner) are skipped so the user can't re-own
/// someone else's event. Both the local `ownerId` and the enqueued `owner_id`
/// payload are stamped with the current profile.
@MainActor
struct DataBackfillService {
    private let context: ModelContext
    private let currentOwnerID: @MainActor () -> UUID?
    private let diagnostics: SyncDiagnosticsCenter
    private let coordinator: OutboxCoordinator

    init(
        context: ModelContext,
        currentOwnerID: @escaping @MainActor () -> UUID?,
        diagnostics: SyncDiagnosticsCenter = .shared
    ) {
        self.context = context
        self.currentOwnerID = currentOwnerID
        self.diagnostics = diagnostics
        self.coordinator = OutboxCoordinator(
            context: context,
            currentOwnerID: currentOwnerID,
            diagnostics: diagnostics
        )
    }

    /// Enqueues every owned local event (and its full subgraph) as id-keyed
    /// `insert` entries, then saves once. Returns the number of events backed up
    /// — `0` (and no enqueue) when no profile is signed in or there is nothing
    /// the current user owns.
    @discardableResult
    func backfill() throws -> Int {
        guard let ownerID = currentOwnerID() else {
            diagnostics.record(
                .push, "backfillSkipped",
                params: ["reason": "noOwner"], severity: .warning
            )
            return 0
        }

        // Deterministic order (by id) keeps the enqueued sequence stable across
        // runs and devices. `UUID` isn't `Comparable`, so sort in memory by its
        // string form rather than in the FetchDescriptor.
        let owned = try context
            .fetch(FetchDescriptor<EventModel>())
            .filter { $0.ownerId == nil || $0.ownerId == ownerID }
            .sorted { $0.id.uuidString < $1.id.uuidString }

        guard !owned.isEmpty else { return 0 }

        // Pass 1 — entity rows in foreign-key order (event → tracks → blocks →
        // vendors → shift records) so every parent's `sequence` precedes its
        // children's.
        for event in owned {
            event.ownerId = ownerID // claim locally for owner-vs-shared gating
            coordinator.enqueueWrite(.insert, event)
            for track in tracks(of: event) {
                coordinator.enqueueWrite(.insert, track)
                for block in blocks(of: track) {
                    coordinator.enqueueWrite(.insert, block)
                }
            }
            for vendor in event.vendors ?? [] {
                coordinator.enqueueWrite(.insert, vendor)
            }
            for record in event.shiftRecords ?? [] {
                coordinator.enqueueWrite(.insert, record)
            }
        }

        // Pass 2 — junctions, after every endpoint row above is enqueued, so an
        // assignment/dependency never precedes a block or vendor it references.
        for event in owned {
            for track in tracks(of: event) {
                for block in blocks(of: track) {
                    for vendor in block.vendors ?? [] {
                        coordinator.enqueueAssignment(.insert, vendor: vendor, block: block)
                    }
                    for dependency in block.dependencies ?? [] {
                        coordinator.enqueueDependency(.insert, block: block, dependsOn: dependency)
                    }
                }
            }
        }

        try context.save()

        diagnostics.record(.push, "backfillEnqueued", params: ["events": String(owned.count)])
        return owned.count
    }

    // MARK: - Deterministic graph traversal

    private func tracks(of event: EventModel) -> [TimelineTrack] {
        (event.tracks ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    private func blocks(of track: TimelineTrack) -> [TimeBlockModel] {
        (track.blocks ?? []).sorted { $0.scheduledStart < $1.scheduledStart }
    }
}
