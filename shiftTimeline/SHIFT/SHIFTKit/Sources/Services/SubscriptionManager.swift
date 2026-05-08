import Foundation
import os
import StoreKit

/// Free-tier gate limits. Single source of truth — never hardcode at call sites.
public enum FreeTier {
    public static let maxActiveEvents = 1
    public static let maxBlocksPerEvent = 15
    public static let maxTemplates = 2
}

/// Result of a `SubscriptionManager.purchase(_:)` call.
public enum PurchaseOutcome: Sendable, Equatable {
    case success
    case userCancelled
    case pending
    case unknown
}

@Observable
@MainActor
public final class SubscriptionManager {

    public static let shared = SubscriptionManager()

    public nonisolated static let productIDs: Set<String> = [
        "shift.pro.sub.monthly",
        "shift.pro.sub.yearly",
        "shift.pro.sub.lifetime",
    ]

    /// Tri-state entitlement: `.unknown` during cold-launch resolution.
    public enum EntitlementState: Sendable, Equatable {
        case unknown, free, pro
    }

    /// Two-state alias for downstream readability.
    public enum Entitlement: Sendable, Equatable {
        case free, pro
    }

    public private(set) var entitlementState: EntitlementState = .unknown
    public private(set) var availableProducts: [Product] = []
    /// Renewal / expiration date for the active auto-renewable subscription.
    /// `nil` for free users and lifetime Pro owners.
    public private(set) var renewalDate: Date?
    public private(set) var isLifetimePro: Bool = false

    /// Confirmed pro only. Await `waitUntilEntitlementResolved()` before feature gates to avoid cold-launch false negatives.
    public var isProUser: Bool { entitlementState == .pro }

    public var currentEntitlement: Entitlement { entitlementState == .pro ? .pro : .free }

    // Convenience accessors for PaywallView
    public var monthlyProduct: Product? { availableProducts.first { $0.id == "shift.pro.sub.monthly" } }
    public var yearlyProduct: Product? { availableProducts.first { $0.id == "shift.pro.sub.yearly" } }
    public var lifetimeProduct: Product? { availableProducts.first { $0.id == "shift.pro.sub.lifetime" } }

    // nonisolated(unsafe): deinit is nonisolated in Swift 6; Task.cancel() is Sendable-safe.
    nonisolated(unsafe) private var updateListenerTask: Task<Void, Never>?
    private var entitlementResolutionContinuations: [CheckedContinuation<EntitlementState, Never>] = []
    private static let logger = Logger(subsystem: "com.shift.store", category: "SubscriptionManager")

    private init() {
        // Start transaction listener before any purchase call to avoid missing updates.
        updateListenerTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handleVerificationResult(result)
            }
        }
        Task { [weak self] in
            await self?.loadProducts()
            await self?.checkCurrentEntitlement()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Public interface

    public func purchase(_ product: Product) async throws -> PurchaseOutcome {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try verification.payloadValue
            await transaction.finish()
            await checkCurrentEntitlement()
            return .success
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            Self.logger.error("Unknown StoreKit PurchaseResult case encountered")
            return .unknown
        }
    }

    public func restore() async throws {
        try await AppStore.sync()
        await checkCurrentEntitlement()
    }

    public func checkCurrentEntitlement() async {
        var foundPro = false
        var foundLifetime = false
        var foundRenewalDate: Date?
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if Self.productIDs.contains(transaction.productID) {
                    foundPro = true
                    // Both `.nonConsumable` and `.nonRenewable` map to lifetime.
                    let isThisLifetime = transaction.productType == .nonConsumable
                        || transaction.productType == .nonRenewable
                    // Lifetime wins over auto-renewing; suppress misleading renewal date.
                    if isThisLifetime {
                        foundLifetime = true
                        foundRenewalDate = nil
                    } else if !foundLifetime {
                        foundRenewalDate = transaction.expirationDate
                    }
                }
            case .unverified(let transaction, let error):
                Self.logger.error("Unverified entitlement for \(transaction.productID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            // Keep iterating until lifetime is confirmed; a later transaction may upgrade the result.
            if foundLifetime { break }
        }
        let resolved: EntitlementState = foundPro ? .pro : .free
        entitlementState = resolved
        isLifetimePro = foundLifetime
        renewalDate = foundRenewalDate
        flushEntitlementResolutionContinuations(with: resolved)
    }

    /// Awaits the first non-`.unknown` entitlement state. Returns immediately if already resolved.
    /// Use before executing Pro-only behavior to avoid false-negatives during the cold-launch race window.
    public func waitUntilEntitlementResolved() async -> EntitlementState {
        if entitlementState != .unknown { return entitlementState }
        return await withCheckedContinuation { continuation in
            entitlementResolutionContinuations.append(continuation)
        }
    }

    // MARK: - Private

    private func loadProducts() async {
        do {
            let products = try await Product.products(for: Self.productIDs)
            availableProducts = products.sorted { $0.price < $1.price }
        } catch {
            Self.logger.error("Failed to load StoreKit products: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleVerificationResult(_ result: VerificationResult<Transaction>) async {
        switch result {
        case .verified(let transaction):
            await transaction.finish()
            await checkCurrentEntitlement()
        case .unverified(let transaction, let error):
            Self.logger.error("Skipped unverified transaction update for \(transaction.productID, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func flushEntitlementResolutionContinuations(with state: EntitlementState) {
        guard state != .unknown else { return }
        let pending = entitlementResolutionContinuations
        entitlementResolutionContinuations.removeAll()
        for continuation in pending {
            continuation.resume(returning: state)
        }
    }
}
