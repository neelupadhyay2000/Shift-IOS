import TelemetryDeck
import Services

/// Centralised analytics wrapper. All TelemetryDeck calls go through here —
/// no raw TelemetryDeck imports or string literals scattered across view files.
///
/// `nonisolated` because TelemetryDeck signalling is thread-safe and signals are
/// emitted from any context (including the `@Sendable` `SyncDiagnosticsCenter`
/// observer, which runs off the main actor). The app target defaults to
/// `@MainActor` isolation, so this opt-out is required.
nonisolated enum AnalyticsService {

    enum Signal: String {
        case appLaunched
        case eventCreated
        case eventGoLive
        case eventCompleted
        case shiftApplied
        case templateUsed
        case vendorInvited
        case pdfExported
        case undoUsed
        case paywallShown
        case purchaseCompleted
        case sessionCompleted

        // Supabase sync funnel — one signal per stage so the sync pipeline is
        // traceable in the TelemetryDeck dashboard.
        case syncAuth
        case syncConnect
        case syncSubscribe
        case syncFetch
        case syncApplyRemote
        case syncPush
        case syncConflict
        case syncNotify

        // Sync-health transitions (SHIFT-668): fired once per status change
        // with `from`/`to` parameters. Filter `to == degraded` for the
        // production alert signal; `to == healthy` marks recovery.
        case syncHealthChanged

        // Marketplace tease funnel (SHIFT-717): measures vendor-vs-planner
        // demand and category mix ahead of the marketplace launch so the E15
        // vendor-first rollout can be data-driven. No PII — waitlistJoined
        // carries only `role` and `category` dimensions (never region text).
        case marketplaceTeaserViewed = "marketplace.teaserViewed"
        case marketplaceWaitlistJoined = "marketplace.waitlistJoined"
    }

    static func send(_ signal: Signal) {
        TelemetryDeck.signal(signal.rawValue)
    }

    static func send(_ signal: Signal, parameters: [String: String]) {
        TelemetryDeck.signal(signal.rawValue, parameters: parameters)
    }

    // MARK: - Diagnostics bridge

    /// Names that fire too frequently to be useful as TelemetryDeck signals.
    /// They remain in the in-app diagnostics log; they're just not forwarded.
    private static let highFrequencyNames: Set<String> = ["pollTick"]

    /// Forwards a `DiagnosticEvent` from `SyncDiagnosticsCenter` to TelemetryDeck.
    /// The event `name` and `severity` ride along as parameters so each funnel
    /// stage is a single signal that can be filtered by outcome.
    static func send(_ event: DiagnosticEvent) {
        guard !highFrequencyNames.contains(event.name) else { return }
        var parameters = event.params
        parameters["name"] = event.name
        parameters["severity"] = event.severity.rawValue
        TelemetryDeck.signal(event.category.signal.rawValue, parameters: parameters)
    }
}

private extension DiagnosticEvent.Category {
    nonisolated var signal: AnalyticsService.Signal {
        switch self {
        case .auth: return .syncAuth
        case .connect: return .syncConnect
        case .subscribe: return .syncSubscribe
        case .fetch: return .syncFetch
        case .applyRemote: return .syncApplyRemote
        case .push: return .syncPush
        case .conflict: return .syncConflict
        case .notify: return .syncNotify
        }
    }
}
