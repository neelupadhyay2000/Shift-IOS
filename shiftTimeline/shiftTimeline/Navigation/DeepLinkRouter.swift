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
    /// Navigate to an event's TimelineBuilderView with EventDetailView in the back stack.
    /// Used after a template is applied so Back takes the user to the event page,
    /// not back into the template browser.
    case newEventTimeline(id: UUID)
    /// Navigate to a vendor's public marketplace profile (`shift://vendor/{id}`).
    case vendorProfile(id: UUID)
}

/// Observable deep-link router that external systems (notification taps,
/// URL opens, Watch complication taps) use to drive navigation into `RootNavigator`.
///
/// Inject via `.environment()` at the app root. `RootNavigator` observes
/// `pendingDestination` and routes accordingly.
@MainActor
@Observable
final class DeepLinkRouter {
    /// Shared instance used by `AppDelegate` and `onOpenURL`.
    static let shared = DeepLinkRouter()

    /// Set this to trigger navigation. `RootNavigator` clears it after routing.
    var pendingDestination: DeepLinkDestination?

    /// The `event_vendors` row id from a tapped invite link, awaiting a
    /// possession-based claim (`claim_invite_by_id`). The app claims it once the
    /// user is authenticated — on the tap if already signed in, otherwise right
    /// after they sign in — then clears it. This is what makes phone-addressed
    /// invites joinable via email OTP, with no phone OTP.
    var pendingInviteVendorID: UUID?

    /// The most recent foreground shift push, surfaced as an in-app banner
    /// instead of a system notification. `RootContainerView` observes
    /// this, shows a transient top toast, and clears it on tap or timeout.
    /// `AppDelegate.willPresent` sets it when it suppresses a foreground `shift-`
    /// notification.
    var foregroundShiftBanner: InAppShiftBanner?

    /// Bumped whenever one of our server pushes (shift / assignment / go-live)
    /// arrives or is tapped — a signal that remote data just changed. The app root
    /// observes it and runs a delta reconcile so the in-app roster/detail refresh
    /// in place, without needing a relaunch.
    var remoteRefreshToken = UUID()

    /// Signals that a server push just landed → trigger a remote refresh.
    func requestRemoteRefresh() {
        remoteRefreshToken = UUID()
    }

    private init() {}

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
    ///   - `shift://event/{eventID}`   → event detail / timeline
    ///   - `shift://live/{eventID}`    → Live Dashboard
    ///   - `shift://vendor/{profileID}` → vendor public marketplace profile
    ///
    /// Returns `true` if the URL was handled.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard url.scheme == "shift",
              let host = url.host else { return false }

        // Vendor invite: shift://invite/{vendorID}?event={eventID}. The claim is
        // identity-based and runs server-side (the app triggers a re-claim + hydrate
        // on receipt); here we just route to the invited event so it's shown once
        // access lands. The event id is in the `event` query, NOT pathComponents[1]
        // (which is the event_vendors row id).
        if host == VendorInviteLink.host {
            guard let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "event" })?.value,
                let eventID = UUID(uuidString: raw) else { return false }
            // The event_vendors row id is the first path component — captured for
            // the possession-based link claim once the user is authenticated.
            if url.pathComponents.count > 1, let vendorID = UUID(uuidString: url.pathComponents[1]) {
                pendingInviteVendorID = vendorID
            }
            pendingDestination = .event(id: eventID)
            return true
        }

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

        // Generic `{scheme}://{host}/{UUID}` (or `?id=UUID`) parse — the id is a
        // vendor profile for the `vendor` host, an event for the others.
        guard let parsedID = UUID(uuidString: rawID) else { return false }

        switch host {
        case "event":
            pendingDestination = .event(id: parsedID)
            return true
        case "live":
            pendingDestination = .live(id: parsedID)
            return true
        case "vendor":
            pendingDestination = .vendorProfile(id: parsedID)
            return true
        default:
            return false
        }
    }
}
