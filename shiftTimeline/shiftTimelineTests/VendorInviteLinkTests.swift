import Foundation
import Testing
@testable import shiftTimeline

@Suite("Vendor invite link & message")
struct VendorInviteLinkTests {

    private let vendorID = UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID()
    private let eventID = UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID()

    @Test func deepLinkStringEncodesVendorAndEvent() {
        let link = VendorInviteLink.deepLinkString(vendorID: vendorID, eventID: eventID)
        #expect(link == "shift://invite/\(vendorID.uuidString)?event=\(eventID.uuidString)")
    }

    /// The link must round-trip through the same `shift://` parser the router uses
    /// (host = action, first path component = id) so the claim flow can parse it.
    @Test func deepLinkURLParsesToInviteHostVendorAndEvent() throws {
        let url = try #require(VendorInviteLink.deepLink(vendorID: vendorID, eventID: eventID))
        #expect(url.scheme == "shift")
        #expect(url.host == VendorInviteLink.host)
        #expect(url.pathComponents.count > 1)
        #expect(url.pathComponents[1] == vendorID.uuidString)

        let event = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "event" })?.value
        #expect(event == eventID.uuidString)
    }

    @Test func messageCarriesDeepLinkAndAppStoreFallback() throws {
        let message = VendorInviteLink.message(
            eventTitle: "Hawkins Wedding",
            vendorID: vendorID,
            eventID: eventID
        )
        let deepLink = VendorInviteLink.deepLinkString(vendorID: vendorID, eventID: eventID)

        #expect(message.subject.contains("Hawkins Wedding"))
        #expect(message.body.contains(deepLink), "Body must carry the deep link")

        let appStore = try #require(VendorInviteLink.appStoreURL?.absoluteString)
        #expect(message.body.contains(appStore), "Body must carry the App Store fallback")
    }

    @Test func messageBodyMentionsEventTitle() {
        let message = VendorInviteLink.message(eventTitle: "Gala 2026", vendorID: vendorID, eventID: eventID)
        #expect(message.body.contains("Gala 2026"))
    }
}
