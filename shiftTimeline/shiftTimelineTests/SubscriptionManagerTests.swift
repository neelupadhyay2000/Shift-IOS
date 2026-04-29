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

    @Test("defaults to free tier immediately after init")
    @MainActor
    func defaultsToFreeTier() {
        let manager = SubscriptionManager()
        #expect(manager.isProUser == false)
        #expect(manager.currentEntitlement == .free)
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
        let manager = SubscriptionManager()
        await manager.checkCurrentEntitlement()
        #expect(manager.isProUser == false)
        #expect(manager.currentEntitlement == .free)
    }

    // MARK: - Entitlement enum

    @Test("Entitlement free and pro cases are not equal")
    func entitlementCasesAreDistinct() {
        #expect(SubscriptionManager.Entitlement.free != SubscriptionManager.Entitlement.pro)
    }
}
