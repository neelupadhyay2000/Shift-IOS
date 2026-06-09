import Foundation
import Services

/// The user-facing health of Supabase sync (SHIFT-664). Deliberately three
/// states — the only distinction a user needs:
/// - **healthy** — everything is up to date.
/// - **pending** — local changes are queued, waiting to reach the server.
/// - **degraded** — a sync stage is failing and the user should know.
enum SyncStatus: String, Sendable, Equatable {
    case healthy
    case pending
    case degraded
}

/// Pure derivation of ``SyncStatus`` from the two signals that matter: how many
/// local writes are still queued, and whether any sync stage is currently
/// failing. Degraded wins (it's the most actionable), then pending, else healthy.
struct SyncHealth: Sendable, Equatable {
    var pendingWrites: Int
    var hasUnresolvedError: Bool

    var status: SyncStatus {
        if hasUnresolvedError { return .degraded }
        if pendingWrites > 0 { return .pending }
        return .healthy
    }
}

/// Folds the diagnostics funnel into the set of sync stages currently failing —
/// the source of the "degraded" signal, derived without coupling to specific
/// event names.
///
/// Rules: an `.error` marks its stage failing; a later `.info` in the **same**
/// stage clears it (the next success in that stage). `.warning`s — e.g. a
/// transient `outboxFlushRetry` while offline — are expected and never degrade
/// the user-facing status. The `notify` category isn't a sync stage, so it's
/// ignored.
struct SyncErrorState: Sendable, Equatable {
    private(set) var failingStages: Set<DiagnosticEvent.Category> = []

    /// The funnel stages that count toward sync health (everything but `notify`).
    static let syncStages: Set<DiagnosticEvent.Category> = [
        .auth, .connect, .subscribe, .fetch, .applyRemote, .push, .conflict,
    ]

    var hasUnresolvedError: Bool { !failingStages.isEmpty }

    mutating func ingest(_ event: DiagnosticEvent) {
        guard Self.syncStages.contains(event.category) else { return }
        switch event.severity {
        case .error: failingStages.insert(event.category)
        case .info: failingStages.remove(event.category)
        case .warning: break
        }
    }

    /// The stage whose failure should drive the surfaced message, most
    /// user-relevant first.
    var primaryFailingStage: DiagnosticEvent.Category? {
        let priority: [DiagnosticEvent.Category] = [
            .auth, .push, .fetch, .applyRemote, .subscribe, .connect, .conflict,
        ]
        return priority.first { failingStages.contains($0) }
    }
}

/// Maps a status (and, when degraded, the failing stage) to the short message
/// surfaced to the user. `nil` for healthy — nothing to say.
enum SyncStatusMessage {
    static func text(
        for status: SyncStatus,
        failingStage: DiagnosticEvent.Category?,
        pendingWrites: Int
    ) -> String? {
        switch status {
        case .healthy:
            return nil
        case .pending:
            return pendingWrites == 1
                ? String(localized: "1 change waiting to sync…")
                : String(localized: "\(pendingWrites) changes waiting to sync…")
        case .degraded:
            return degradedText(for: failingStage)
        }
    }

    static func degradedText(for stage: DiagnosticEvent.Category?) -> String {
        switch stage {
        case .auth:
            return String(localized: "Sign in to keep your events in sync.")
        case .push:
            return String(localized: "Some changes haven’t synced yet. We’ll keep trying.")
        case .fetch:
            return String(localized: "Couldn’t refresh from the server. Pull to retry.")
        case .applyRemote:
            return String(localized: "A sync update couldn’t be applied.")
        case .subscribe, .connect:
            return String(localized: "Live updates are paused. Reconnecting…")
        case .conflict:
            return String(localized: "Resolving a sync conflict…")
        case .notify, .none:
            return String(localized: "Sync is having trouble. We’ll keep retrying.")
        }
    }
}

extension SyncStatus {
    /// Short status label for the indicator.
    var label: String {
        switch self {
        case .healthy: return String(localized: "Synced")
        case .pending: return String(localized: "Syncing…")
        case .degraded: return String(localized: "Sync issue")
        }
    }

    /// SF Symbol name for the indicator glyph.
    var symbolName: String {
        switch self {
        case .healthy: return "checkmark.icloud"
        case .pending: return "arrow.triangle.2.circlepath.icloud"
        case .degraded: return "exclamationmark.icloud"
        }
    }
}
