import Foundation
import os
import StoreKit

@Observable
@MainActor
public final class SubscriptionManager {

    public static let shared = SubscriptionManager()

    public nonisolated static let productIDs: Set<String> = [
        "shift.pro.sub.monthly",
        "shift.pro.sub.yearly",
        "shift.pro.sub.lifetime",
    ]

    public enum Entitlement: Sendable, Equatable {
        case free, pro
    }

    public private(set) var isProUser = false
    public private(set) var currentEntitlement: Entitlement = .free
    public private(set) var availableProducts: [Product] = []

    // Convenience accessors for PaywallView
    public var monthlyProduct: Product? { availableProducts.first { $0.id == "shift.pro.sub.monthly" } }
    public var yearlyProduct: Product? { availableProducts.first { $0.id == "shift.pro.sub.yearly" } }
    public var lifetimeProduct: Product? { availableProducts.first { $0.id == "shift.pro.sub.lifetime" } }

    private var updateListenerTask: Task<Void, Never>?
    private static let logger = Logger(subsystem: "com.shift.store", category: "SubscriptionManager")

    public init() {
        // Transaction listener must be started before any purchase call to avoid missing updates.
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

    // MARK: - Public interface

    public func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try verification.payloadValue
            await transaction.finish()
            await checkCurrentEntitlement()
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    public func restore() async throws {
        try await AppStore.sync()
        await checkCurrentEntitlement()
    }

    public func checkCurrentEntitlement() async {
        var foundPro = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID.hasPrefix("shift.pro") {
                foundPro = true
                break
            }
        }
        isProUser = foundPro
        currentEntitlement = foundPro ? .pro : .free
    }

    // MARK: - Private

    private func loadProducts() async {
        do {
            let products = try await Product.products(for: Self.productIDs)
            availableProducts = products.sorted { $0.price < $1.price }
        } catch {
            Self.logger.error("Failed to load StoreKit products: \(error)")
        }
    }

    private func handleVerificationResult(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        await transaction.finish()
        await checkCurrentEntitlement()
    }
}
