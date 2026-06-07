import Foundation
import Services
import Testing
@testable import shiftTimeline

/// SHIFT-648: when the app is foregrounded, a shift push is suppressed as a
/// system notification and surfaced as an in-app banner instead. These cover the
/// pure builder that turns a foreground `shift-` notification into the banner model.
@Suite("Foreground shift banner (SHIFT-648)")
struct ForegroundShiftBannerTests {

    @Test("a foregrounded shift notification produces an in-app banner")
    func buildsBannerForShiftNotification() throws {
        let eventID = UUID()
        let banner = try #require(RemoteShiftPushHandler.makeForegroundBanner(
            identifier: "shift-\(UUID().uuidString)",
            title: "Timeline Update",
            body: "Timeline moved +15 min — First Dance up next",
            userInfo: [VendorShiftNotificationContent.eventIDKey: eventID.uuidString]
        ))
        #expect(banner.title == "Timeline Update")
        #expect(banner.body.contains("+15 min"))
        #expect(banner.eventID == eventID)
    }

    @Test("a non-shift foreground notification produces no in-app banner")
    func ignoresNonShiftNotification() {
        let banner = RemoteShiftPushHandler.makeForegroundBanner(
            identifier: "live-restart",
            title: "Live",
            body: "Resume",
            userInfo: ["eventID": UUID().uuidString]
        )
        #expect(banner == nil)
    }

    @Test("a shift notification missing an event id produces no banner")
    func ignoresShiftNotificationWithoutEventID() {
        let banner = RemoteShiftPushHandler.makeForegroundBanner(
            identifier: "shift-\(UUID().uuidString)",
            title: "Timeline Update",
            body: "Moved",
            userInfo: [:]
        )
        #expect(banner == nil)
    }
}
