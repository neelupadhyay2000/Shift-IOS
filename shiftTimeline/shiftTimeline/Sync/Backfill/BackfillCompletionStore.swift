import Foundation

/// Records, per account, whether the one-time post-migration backfill
/// has already run on **this device**, so it fires exactly once per
/// account instead of re-enqueuing the entire local graph on every launch.
///
/// Keyed by Supabase profile id rather than a single global boolean: signing
/// into a different account on the same device still triggers that account's
/// backfill. The flag is intentionally *local* (per device) — two devices on
/// the same account each run once, and the duplicate uploads collapse
/// server-side via the id-keyed Outbox upsert, so no shared/remote
/// flag is needed.
///
/// Mirrors `LastPulledStore`: a small per-key value in `UserDefaults`; no
/// SwiftData table is warranted for a single boolean per account.
nonisolated struct BackfillCompletionStore {
    private let defaults: UserDefaults
    private let keyPrefix: String

    init(defaults: UserDefaults = .standard, keyPrefix: String = "migration.backfillCompleted") {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    /// `true` once the backfill has completed for `profileID` on this device.
    func hasCompleted(for profileID: UUID) -> Bool {
        defaults.bool(forKey: storageKey(profileID))
    }

    /// Records that the backfill completed for `profileID`. Idempotent.
    func markCompleted(for profileID: UUID) {
        defaults.set(true, forKey: storageKey(profileID))
    }

    private func storageKey(_ profileID: UUID) -> String {
        "\(keyPrefix).\(profileID.uuidString)"
    }
}
