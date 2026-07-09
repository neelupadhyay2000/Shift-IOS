import Foundation
import Testing
@testable import shiftTimeline

/// Locks the wire contract for the marketplace-launch announcement push (E24
/// Task 1): the payload key + role values must match the
/// `marketplace-launch-notify` Edge Function, and the tap must route vendors
/// into profile setup (seed supply first) and planners into Marketplace home.
@Suite("Marketplace launch push")
struct MarketplaceLaunchPushTests {

    // MARK: - Wire contract

    @Test("payload key matches the Edge Function's MARKETPLACE_LAUNCH_KEY")
    func keyMatchesEdgeFunction() {
        #expect(RemoteShiftPushHandler.marketplaceLaunchKey == "com.shift.marketplaceLaunch")
    }

    @Test("role raw values match the Edge Function wave values")
    func roleRawValuesMatchSQLAndFunction() {
        #expect(MarketplaceLaunchRole.vendor.rawValue == "vendor")
        #expect(MarketplaceLaunchRole.planner.rawValue == "planner")
    }

    // MARK: - Parse

    @Test("parses vendor and planner roles from userInfo")
    func parsesKnownRoles() {
        let vendor = RemoteShiftPushHandler.parseMarketplaceLaunchRole(
            ["com.shift.marketplaceLaunch": "vendor"]
        )
        let planner = RemoteShiftPushHandler.parseMarketplaceLaunchRole(
            ["com.shift.marketplaceLaunch": "planner"]
        )
        #expect(vendor == .vendor)
        #expect(planner == .planner)
    }

    @Test("unknown role and missing key parse as nil (forward-compatible)")
    func rejectsUnknownAndMissing() {
        #expect(RemoteShiftPushHandler.parseMarketplaceLaunchRole(
            ["com.shift.marketplaceLaunch": "sponsor"]
        ) == nil)
        #expect(RemoteShiftPushHandler.parseMarketplaceLaunchRole([:]) == nil)
        #expect(RemoteShiftPushHandler.parseMarketplaceLaunchRole(
            ["com.shift.marketplaceLaunch": 7]
        ) == nil)
    }

    @Test("a launch push is not mistaken for a shift or request push")
    func doesNotCollideWithOtherPushTypes() {
        let userInfo: [AnyHashable: Any] = ["com.shift.marketplaceLaunch": "vendor"]
        #expect(RemoteShiftPushHandler.parse(userInfo) == nil)
        #expect(RemoteShiftPushHandler.parseRequestID(userInfo) == nil)
    }

    // MARK: - Route

    @Test("vendor tap routes to the marketplace launch destination with vendor role")
    @MainActor
    func vendorTapRoutes() {
        let router = DeepLinkRouter.shared
        defer { router.pendingDestination = nil }

        RemoteShiftPushHandler.routeMarketplaceLaunchTap(.vendor, router: router)
        #expect(router.pendingDestination == .marketplaceLaunch(role: .vendor))
    }

    @Test("planner tap routes to the marketplace launch destination with planner role")
    @MainActor
    func plannerTapRoutes() {
        let router = DeepLinkRouter.shared
        defer { router.pendingDestination = nil }

        RemoteShiftPushHandler.routeMarketplaceLaunchTap(.planner, router: router)
        #expect(router.pendingDestination == .marketplaceLaunch(role: .planner))
    }
}
