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

        // Sync/share diagnostics — one signal per funnel stage so the
        // planner→vendor pipeline is traceable in the TelemetryDeck dashboard.
        case syncMirror
        case syncIdentity
        case syncAccount
        case syncSubscription
        case syncShareCreate
        case syncParentRepair
        case syncShareAccept
        case syncFetch
        case syncMerge
        case syncPush
        case syncNotify
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
        case .mirror: return .syncMirror
        case .identity: return .syncIdentity
        case .account: return .syncAccount
        case .subscription: return .syncSubscription
        case .shareCreate: return .syncShareCreate
        case .parentRepair: return .syncParentRepair
        case .shareAccept: return .syncShareAccept
        case .fetch: return .syncFetch
        case .merge: return .syncMerge
        case .push: return .syncPush
        case .notify: return .syncNotify
        }
    }
}
