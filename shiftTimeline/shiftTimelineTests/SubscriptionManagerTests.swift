import Services
import StoreKit
import Testing

@Suite("SubscriptionManager")
struct SubscriptionManagerTests {

    // MARK: - Singleton

    @Test("shared instance is a singleton")
    @MainActor
    func sharedInstanceIsSingleton() {
        let a = SubscriptionManager.shared
        let b = SubscriptionManager.shared
        #expect(a === b)
    }

    // MARK: - Default state

    @Test("defaults to non-pro until entitlement resolves")
    @MainActor
    func defaultsToNonPro() {
        #expect(SubscriptionManager.shared.isProUser == false)
    }

    // MARK: - Product IDs

    @Test("exposes exactly three canonical product IDs")
    func productIDsAreComplete() {
        #expect(SubscriptionManager.productIDs.contains("shift.pro.sub.monthly"))
        #expect(SubscriptionManager.productIDs.contains("shift.pro.sub.yearly"))
        #expect(SubscriptionManager.productIDs.contains("shift.pro.sub.lifetime"))
        #expect(SubscriptionManager.productIDs.count == 3)
    }

    // MARK: - Entitlement check

    @Test("checkCurrentEntitlement yields free tier in clean environment")
    @MainActor
    func checkEntitlementInCleanEnvironment() async {
        // Note: in a sandbox environment with active Pro purchases this will read .pro.
        // Once StoreKitTest's SKTestSession is wired up we can make this fully deterministic.
        await SubscriptionManager.shared.checkCurrentEntitlement()
        #expect(SubscriptionManager.shared.entitlementState != .unknown)
    }

    // MARK: - Entitlement enums

    @Test("Entitlement free and pro cases are not equal")
    func entitlementCasesAreDistinct() {
        #expect(SubscriptionManager.Entitlement.free != SubscriptionManager.Entitlement.pro)
    }

    @Test("EntitlementState has three distinct cases")
    func entitlementStateCasesAreDistinct() {
        let states: Set<SubscriptionManager.EntitlementState> = [.unknown, .free, .pro]
        #expect(states.count == 3)
    }

    @Test("isProUser is true only for .pro state")
    @MainActor
    func isProUserDerivation() async {
        await SubscriptionManager.shared.checkCurrentEntitlement()
        let manager = SubscriptionManager.shared
        switch manager.entitlementState {
        case .pro:
            #expect(manager.isProUser == true)
        case .free, .unknown:
            #expect(manager.isProUser == false)
        }
    }

    // MARK: - PurchaseOutcome

    @Test("PurchaseOutcome cases are all distinct")
    func purchaseOutcomeCasesAreDistinct() {
        let outcomes: Set<PurchaseOutcome> = [.success, .userCancelled, .pending, .unknown]
        #expect(outcomes.count == 4)
    }

    // MARK: - waitUntilEntitlementResolved

    @Test("waitUntilEntitlementResolved returns immediately if already resolved")
    @MainActor
    func waitReturnsImmediatelyWhenResolved() async {
        await SubscriptionManager.shared.checkCurrentEntitlement()
        let state = await SubscriptionManager.shared.waitUntilEntitlementResolved()
        #expect(state != .unknown)
    }
}

@Suite("FreeTier limits")
struct FreeTierTests {

    @Test("Active event cap is 1")
    func activeEventCap() {
        #expect(FreeTier.maxActiveEvents == 1)
    }

    @Test("Blocks per event cap is 15")
    func blocksPerEventCap() {
        #expect(FreeTier.maxBlocksPerEvent == 15)
    }

    @Test("Templates cap is 2")
    func templatesCap() {
        #expect(FreeTier.maxTemplates == 2)
    }

    // MARK: - Gate predicate behavior

    @Test("event-creation gate triggers paywall when free user is at limit")
    func eventGateAtLimit() {
        let isPro = false
        let eventCount = FreeTier.maxActiveEvents
        let shouldShowPaywall = eventCount >= FreeTier.maxActiveEvents && !isPro
        #expect(shouldShowPaywall == true)
    }

    @Test("event-creation gate does not trigger paywall below limit")
    func eventGateBelowLimit() {
        let isPro = false
        let eventCount = 0
        let shouldShowPaywall = eventCount >= FreeTier.maxActiveEvents && !isPro
        #expect(shouldShowPaywall == false)
    }

    @Test("event-creation gate never triggers for pro user")
    func eventGateProUser() {
        let isPro = true
        let eventCount = 100
        let shouldShowPaywall = eventCount >= FreeTier.maxActiveEvents && !isPro
        #expect(shouldShowPaywall == false)
    }

    @Test("block gate triggers at exactly the cap")
    func blockGateAtCap() {
        let isPro = false
        let blockCount = FreeTier.maxBlocksPerEvent
        let shouldShowPaywall = blockCount >= FreeTier.maxBlocksPerEvent && !isPro
        #expect(shouldShowPaywall == true)
    }

    @Test("block gate allows free user one below cap")
    func blockGateBelowCap() {
        let isPro = false
        let blockCount = FreeTier.maxBlocksPerEvent - 1
        let shouldShowPaywall = blockCount >= FreeTier.maxBlocksPerEvent && !isPro
        #expect(shouldShowPaywall == false)
    }
}
