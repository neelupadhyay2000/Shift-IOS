import Foundation
import SwiftUI

/// The action the router should perform when a deep-link arrives.
enum DeepLinkDestination: Equatable {
    /// Navigate to event detail / timeline view.
    case event(id: UUID)
    /// Navigate directly to the Live Dashboard for an event.
    case live(id: UUID)
    /// Navigate to the Event Roster (events list).
    case roster
}

/// Observable deep-link router that external systems (notification taps,
/// URL opens, Watch complication taps, CKShare acceptance) use to drive
/// navigation into `RootNavigator`.
///
/// Inject via `.environment()` at the app root. `RootNavigator` observes
/// `pendingDestination` and routes accordingly.
@Observable
final class DeepLinkRouter {
    /// Shared instance used by `AppDelegate` and `onOpenURL`.
    static let shared = DeepLinkRouter()

    /// Set this to trigger navigation. `RootNavigator` clears it after routing.
    var pendingDestination: DeepLinkDestination?

    /// Convenience — kept for backward compatibility with existing callers.
    var pendingEventID: UUID? {
        get {
            if case .event(let id) = pendingDestination { return id }
            return nil
        }
        set {
            if let id = newValue {
                pendingDestination = .event(id: id)
            } else if case .event = pendingDestination {
                pendingDestination = nil
            }
        }
    }

    // MARK: - URL Parsing

    /// Custom URL scheme: `shift://`
    /// Supported paths:
    ///   - `shift://event/{eventID}` → event detail / timeline
    ///   - `shift://live/{eventID}`  → Live Dashboard
    ///
    /// Returns `true` if the URL was handled.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard url.scheme == "shift",
              let host = url.host else { return false }

        // Support both shift://event/UUID and shift://event?id=UUID
        let rawID: String
        if let queryID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "id" })?.value {
            rawID = queryID
        } else if url.pathComponents.count > 1 {
            rawID = url.pathComponents[1]
        } else {
            return false
        }

        guard let eventID = UUID(uuidString: rawID) else { return false }

        switch host {
        case "event":
            pendingDestination = .event(id: eventID)
            return true
        case "live":
            pendingDestination = .live(id: eventID)
            return true
        default:
            return false
        }
    }
}
