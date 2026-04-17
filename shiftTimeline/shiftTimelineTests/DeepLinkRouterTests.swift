import Foundation
import Testing
@testable import shiftTimeline

@Suite("DeepLinkRouter URL Parsing")
@MainActor
struct DeepLinkRouterTests {

    // MARK: - Event URL

    @Test func eventURLSetsEventDestination() {
        let router = DeepLinkRouter.shared
        let id = UUID()
        let url = URL(string: "shift://event/\(id.uuidString)")!

        let handled = router.handle(url: url)

        #expect(handled == true)
        #expect(router.pendingDestination == .event(id: id))
        router.pendingDestination = nil
    }

    // MARK: - Live URL

    @Test func liveURLSetsLiveDestination() {
        let router = DeepLinkRouter.shared
        let id = UUID()
        let url = URL(string: "shift://live/\(id.uuidString)")!

        let handled = router.handle(url: url)

        #expect(handled == true)
        #expect(router.pendingDestination == .live(id: id))
        router.pendingDestination = nil
    }

    // MARK: - Unknown Host

    @Test func unknownHostReturnsFalse() {
        let router = DeepLinkRouter.shared
        let url = URL(string: "shift://unknown/\(UUID().uuidString)")!

        let handled = router.handle(url: url)

        #expect(handled == false)
    }

    // MARK: - Invalid UUID

    @Test func invalidUUIDReturnsFalse() {
        let router = DeepLinkRouter.shared
        let url = URL(string: "shift://event/not-a-uuid")!

        let handled = router.handle(url: url)

        #expect(handled == false)
    }

    // MARK: - Wrong Scheme

    @Test func wrongSchemeReturnsFalse() {
        let router = DeepLinkRouter.shared
        let url = URL(string: "https://event/\(UUID().uuidString)")!

        let handled = router.handle(url: url)

        #expect(handled == false)
    }

    // MARK: - Query Parameter ID

    @Test func eventURLWithQueryIDWorks() {
        let router = DeepLinkRouter.shared
        let id = UUID()
        let url = URL(string: "shift://event?id=\(id.uuidString)")!

        let handled = router.handle(url: url)

        #expect(handled == true)
        #expect(router.pendingDestination == .event(id: id))
        router.pendingDestination = nil
    }

    // MARK: - pendingEventID Compatibility

    @Test func pendingEventIDSetterTriggersEventDestination() {
        let router = DeepLinkRouter.shared
        let id = UUID()
        router.pendingEventID = id

        #expect(router.pendingDestination == .event(id: id))
        router.pendingDestination = nil
    }

    @Test func pendingEventIDGetterReadsEventDestination() {
        let router = DeepLinkRouter.shared
        let id = UUID()
        router.pendingDestination = .event(id: id)

        #expect(router.pendingEventID == id)
        router.pendingDestination = nil
    }

    @Test func pendingEventIDReturnsNilForLiveDestination() {
        let router = DeepLinkRouter.shared
        router.pendingDestination = .live(id: UUID())

        #expect(router.pendingEventID == nil)
        router.pendingDestination = nil
    }
}
