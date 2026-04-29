import TelemetryDeck

/// Centralised analytics wrapper. All TelemetryDeck calls go through here —
/// no raw TelemetryDeck imports or string literals scattered across view files.
enum AnalyticsService {

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
    }

    static func send(_ signal: Signal) {
        TelemetryDeck.signal(signal.rawValue)
    }

    static func send(_ signal: Signal, parameters: [String: String]) {
        TelemetryDeck.signal(signal.rawValue, parameters: parameters)
    }
}
