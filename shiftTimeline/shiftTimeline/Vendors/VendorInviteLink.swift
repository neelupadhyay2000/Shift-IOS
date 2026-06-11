import Foundation

/// Builds the vendor invite a planner delivers over iMessage / email:
/// a `shift://invite/...` deep link plus the pre-filled composer message that
/// carries it and an App Store fallback for recipients who don't have SHIFT yet.
///
/// The link is intentionally shaped to round-trip through the same `shift://`
/// parser `DeepLinkRouter` uses — `host` = action, first path component = id —
/// so the claim flow reads it back with a plain parse:
/// `host == VendorInviteLink.host`, `pathComponents[1]` = the `event_vendors` row
/// id, and `?event=` = the event id.
nonisolated enum VendorInviteLink {

    /// Deep-link scheme registered in `Info.plist` (`CFBundleURLSchemes`).
    static let scheme = "shift"

    /// Deep-link host (the router's "action") identifying an invite to claim.
    static let host = "invite"

    /// App Store product-page id for SHIFT (App Store Connect → App Information →
    /// Apple ID = `6761797338`).
    static let appStoreID = "id6761797338"

    /// "Don't have SHIFT yet?" fallback the invite body links to.
    static let appStoreURL = URL(string: "https://apps.apple.com/app/\(appStoreID)")

    /// A composer-ready invite: `subject` (email composer) + `body` carrying the
    /// deep link and the App Store fallback.
    struct InviteMessage: Equatable {
        let subject: String
        let body: String
    }

    /// `shift://invite/{vendorID}?event={eventID}` — the identity-locked, claimable
    /// invite link. `vendorID` is the `event_vendors` row id; `eventID` scopes the
    /// claim to one event.
    static func deepLinkString(vendorID: UUID, eventID: UUID) -> String {
        "\(scheme)://\(host)/\(vendorID.uuidString)?event=\(eventID.uuidString)"
    }

    /// The deep link as a `URL`, or `nil` if it somehow fails to parse.
    static func deepLink(vendorID: UUID, eventID: UUID) -> URL? {
        URL(string: deepLinkString(vendorID: vendorID, eventID: eventID))
    }

    /// Builds the pre-filled invite message for `eventTitle`, carrying the deep link
    /// and the App Store fallback in the body.
    static func message(eventTitle: String, vendorID: UUID, eventID: UUID) -> InviteMessage {
        let link = deepLinkString(vendorID: vendorID, eventID: eventID)
        let appStore = appStoreURL?.absoluteString ?? ""
        let subject = String(localized: "SHIFT timeline invite: \(eventTitle)")
        let body = String(localized: """
            You're invited to the SHIFT timeline for \(eventTitle).

            Open this link on your iPhone to see the schedule and get live updates:
            \(link)

            Don't have SHIFT yet? Download it here, then open the invite link again:
            \(appStore)
            """)
        return InviteMessage(subject: subject, body: body)
    }
}
