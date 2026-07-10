import Services
import StoreKit
import Testing

/// `.serialized` because several tests mutate `SubscriptionManager.shared` — a
/// singleton — across `await` points. Run in parallel, one test's save/restore of
/// `compedUntil` would be observed by another mid-flight.
@Suite("SubscriptionManager", .serialized)
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

    /// `isProUser` is `entitlementState == .pro || isComped || isDemoPro`, so this
    /// test is really about the *StoreKit* default. It must neutralise the other
    /// two inputs first, because `SubscriptionManager.shared` is a singleton that
    /// rehydrates `compedUntil` from `UserDefaults` in `init()`.
    ///
    /// That bit us once the founding-cohort comp shipped: any simulator where the
    /// app has been run and signed in carries a live comp in the shared defaults,
    /// which leaked straight into the test host. The test wasn't hermetic — it
    /// only ever passed because no account had a comp.
    @Test("defaults to non-pro until entitlement resolves")
    @MainActor
    func defaultsToNonPro() {
        let manager = SubscriptionManager.shared
        let savedComp = manager.compedUntil
        let savedDemo = manager.isDemoPro
        defer {
            // Restore, so a later run against this simulator still sees its comp.
            manager.compedUntil = savedComp
            manager.isDemoPro = savedDemo
        }

        manager.compedUntil = nil
        manager.isDemoPro = false

        // Deliberately not asserting on `entitlementState`: a simulator with an
        // active sandbox purchase legitimately reads `.pro` (see
        // `checkEntitlementInCleanEnvironment`).
        #expect(manager.isProUser == false)
    }

    /// The other half of the contract: a live comp *does* grant Pro through the
    /// same property, independent of StoreKit. (This is the path the founding
    /// cohort takes; the failure above proved it works end-to-end.)
    @Test("a live comp grants pro without a StoreKit entitlement")
    @MainActor
    func liveCompGrantsPro() {
        let manager = SubscriptionManager.shared
        let savedComp = manager.compedUntil
        let savedDemo = manager.isDemoPro
        defer {
            manager.compedUntil = savedComp
            manager.isDemoPro = savedDemo
        }

        manager.isDemoPro = false
        manager.compedUntil = Date.now.addingTimeInterval(60 * 60 * 24)

        #expect(manager.isComped == true)
        #expect(manager.isProUser == true)
    }

    // MARK: - Complimentary access

    @Test("no comp window grants nothing")
    func nilCompGrantsNothing() {
        #expect(SubscriptionManager.isCompActive(nil) == false)
    }

    @Test("a future expiry grants comp")
    func futureCompIsActive() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let until = now.addingTimeInterval(60)
        #expect(SubscriptionManager.isCompActive(until, now: now) == true)
    }

    @Test("comp lapses at the expiry instant")
    func compLapsesAtExpiry() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        #expect(SubscriptionManager.isCompActive(now, now: now) == false)
        #expect(SubscriptionManager.isCompActive(now.addingTimeInterval(-1), now: now) == false)
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

    /// With comp and demo neutralised, `isProUser` tracks the StoreKit entitlement
    /// exactly. (Its full definition is `.pro || isComped || isDemoPro` — the other
    /// two inputs are covered by `liveCompGrantsPro` and the `isCompActive` tests.)
    @Test("with no comp or demo override, isProUser tracks the StoreKit entitlement")
    @MainActor
    func isProUserDerivation() async {
        let manager = SubscriptionManager.shared
        let savedComp = manager.compedUntil
        let savedDemo = manager.isDemoPro
        defer {
            manager.compedUntil = savedComp
            manager.isDemoPro = savedDemo
        }
        manager.compedUntil = nil
        manager.isDemoPro = false

        await manager.checkCurrentEntitlement()
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

/// `FreeTier` is now remote-configurable (`app_config.free_tier`), cached to
/// `UserDefaults`, and backed by a compiled fallback. These tests pin the
/// fallback, the apply/cache round-trip, and the gate predicates — the last of
/// which are written against `FreeTier.*` so they stay correct at any limits.
@Suite("FreeTier limits", .serialized)
@MainActor
struct FreeTierTests {

    /// Every test starts from the compiled fallback, and leaves it that way.
    init() { FreeTier.resetToFallback() }

    // MARK: - Fallback

    @Test("the compiled fallback is the widened free plan")
    func fallbackIsWidened() {
        #expect(FreeTierLimits.fallback.maxActiveEvents == 5)
        #expect(FreeTierLimits.fallback.maxBlocksPerEvent == 40)
        #expect(FreeTierLimits.fallback.maxTemplates == 10)
    }

    @Test("with no cached config, the limits are the fallback")
    func limitsDefaultToFallback() {
        #expect(FreeTier.limits == .fallback)
        #expect(FreeTier.maxActiveEvents == FreeTierLimits.fallback.maxActiveEvents)
        #expect(FreeTier.maxBlocksPerEvent == FreeTierLimits.fallback.maxBlocksPerEvent)
        #expect(FreeTier.maxTemplates == FreeTierLimits.fallback.maxTemplates)
    }

    // MARK: - Remote apply + cache

    @Test("applying remote limits takes effect immediately")
    func applyTakesEffect() {
        defer { FreeTier.resetToFallback() }
        FreeTier.apply(FreeTierLimits(maxActiveEvents: 2, maxBlocksPerEvent: 20, maxTemplates: 3))
        #expect(FreeTier.maxActiveEvents == 2)
        #expect(FreeTier.maxBlocksPerEvent == 20)
        #expect(FreeTier.maxTemplates == 3)
    }

    @Test("applied limits are cached so a cold offline launch keeps them")
    func applyIsCached() throws {
        defer { FreeTier.resetToFallback() }
        let remote = FreeTierLimits(maxActiveEvents: 7, maxBlocksPerEvent: 70, maxTemplates: 7)
        FreeTier.apply(remote)

        // Simulate the next cold launch reading the cache.
        let data = try #require(UserDefaults.standard.data(forKey: "freeTier.limits"))
        let decoded = try JSONDecoder().decode(FreeTierLimits.self, from: data)
        #expect(decoded == remote)
    }

    @Test("reset clears the cache and returns to the fallback")
    func resetClearsCache() {
        FreeTier.apply(FreeTierLimits(maxActiveEvents: 9, maxBlocksPerEvent: 9, maxTemplates: 9))
        FreeTier.resetToFallback()
        #expect(FreeTier.limits == .fallback)
        #expect(UserDefaults.standard.data(forKey: "freeTier.limits") == nil)
    }

    @Test("the backend's jsonb keys decode into FreeTierLimits")
    func decodesBackendPayload() throws {
        // Exactly the value seeded into app_config.free_tier.
        let json = #"{"maxActiveEvents": 5, "maxBlocksPerEvent": 40, "maxTemplates": 10}"#
        let decoded = try JSONDecoder().decode(FreeTierLimits.self, from: Data(json.utf8))
        #expect(decoded == .fallback)
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
