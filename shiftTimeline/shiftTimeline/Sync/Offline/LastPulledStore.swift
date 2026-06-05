import Foundation

/// The scope a delta pull is watermarked against.
///
/// - `.account`: one watermark for the whole signed-in account — the foreground
///   catch-up pulls everything that changed across all accessible events.
/// - `.event(id)`: a per-event watermark, for pulling a single event's delta
///   (e.g. when its detail view opens).
nonisolated enum SyncScope: Hashable {
    case account
    case event(UUID)

    fileprivate var key: String {
        switch self {
        case .account: return "account"
        case let .event(id): return "event.\(id.uuidString)"
        }
    }
}

/// Persists the `lastPulledAt` watermark per ``SyncScope`` so delta pulls
/// (SHIFT-614) know where to resume: the next pull fetches rows with
/// `updated_at > lastPulled` (plus tombstones) and, on success, advances the
/// watermark. Survives relaunch — that's what lets a device that was offline or
/// backgrounded catch up on next foreground without a manual refresh.
///
/// Backed by `UserDefaults` (a watermark is a single small timestamp per scope;
/// no need for a SwiftData table). The recorded value should be a
/// **server-derived** timestamp (the max `updated_at` seen, or the server's
/// fetch-time `now()`), never the device clock, so clock skew can't make a pull
/// skip rows — that choice belongs to the SHIFT-614 fetch.
nonisolated struct LastPulledStore {
    private let defaults: UserDefaults
    private let keyPrefix: String

    init(defaults: UserDefaults = .standard, keyPrefix: String = "sync.lastPulledAt") {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    /// The watermark for `scope`, or `nil` if it has never been pulled (a first
    /// pull should fall back to a full hydration).
    func lastPulled(for scope: SyncScope) -> Date? {
        defaults.object(forKey: storageKey(scope)) as? Date
    }

    /// Advances the watermark for `scope` after a successful pull.
    func recordPull(at date: Date, for scope: SyncScope) {
        defaults.set(date, forKey: storageKey(scope))
    }

    /// Clears a single scope's watermark (forces a full re-pull of that scope).
    func reset(_ scope: SyncScope) {
        defaults.removeObject(forKey: storageKey(scope))
    }

    /// Clears every watermark this store owns — e.g. on sign-out, so the next
    /// account fully re-hydrates rather than inheriting a stale watermark.
    func resetAll() {
        let prefix = "\(keyPrefix)."
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private func storageKey(_ scope: SyncScope) -> String {
        "\(keyPrefix).\(scope.key)"
    }
}
