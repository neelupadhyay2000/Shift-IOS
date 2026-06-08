import Foundation
import Services
import SwiftData

/// Drives the one-time post-migration backfill, gating it to run at most once
/// per account. Abstracted as a protocol so `SupabaseAuthService` can invoke it
/// as another idempotent post-sign-in side effect and tests can substitute a
/// fake.
@MainActor
protocol DataBackfilling {
    /// Runs the backfill for `profileID` the first time it's called for that
    /// account on this device; a no-op on every call thereafter.
    func runIfNeeded(profileID: UUID) async
}

/// Production ``DataBackfilling``: consults ``BackfillCompletionStore``, runs
/// ``DataBackfillService`` once per account, and records completion.
///
/// The cross-device duplicate case (the same account signed in on two devices)
/// is handled by the id-keyed Outbox upsert in ``DataBackfillService`` — both
/// devices enqueue the same row ids, which converge server-side — not by this
/// per-device flag. A failed run is intentionally **not** marked complete, so a
/// transient error retries on the next session establishment.
@MainActor
final class DataBackfillRunner: DataBackfilling {
    private let context: ModelContext
    private let store: BackfillCompletionStore
    private let diagnostics: SyncDiagnosticsCenter

    init(
        context: ModelContext,
        store: BackfillCompletionStore = BackfillCompletionStore(),
        diagnostics: SyncDiagnosticsCenter = .shared
    ) {
        self.context = context
        self.store = store
        self.diagnostics = diagnostics
    }

    func runIfNeeded(profileID: UUID) async {
        guard !store.hasCompleted(for: profileID) else { return }

        let service = DataBackfillService(
            context: context,
            currentOwnerID: { profileID },
            diagnostics: diagnostics
        )
        do {
            let events = try service.backfill()
            // Marked only after a clean enqueue — a throw above leaves the flag
            // unset so the next launch retries.
            store.markCompleted(for: profileID)
            diagnostics.record(
                .push, "backfillRanOnce",
                params: ["profile": profileID.uuidString, "events": String(events)]
            )
        } catch {
            diagnostics.record(
                .push, "backfillRunFailed",
                params: ["profile": profileID.uuidString, "error": String(describing: error)],
                severity: .error
            )
        }
    }
}
