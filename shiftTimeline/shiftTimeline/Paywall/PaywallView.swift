import StoreKit
import SwiftUI
import Services

// MARK: - Trigger

enum PaywallTrigger: String, Identifiable, Sendable {
    case eventLimit
    case blockLimit
    case vendorSharing
    case liveActivity
    case pdfExport
    case templates
    case widgets

    var id: String { rawValue }
}

// MARK: - View

struct PaywallView: View {

    let trigger: PaywallTrigger

    @Environment(\.dismiss) private var dismiss

    @State private var selectedProduct: Product?
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var showNoRestoreAlert = false
    @State private var showRestoreErrorAlert = false
    @State private var purchaseErrorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    heroSection
                    featureTable
                    pricingSection
                    ctaSection
                    restoreButton
                    legalText
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                    .accessibilityLabel(String(localized: "Close"))
                }
            }
        }
        .onAppear { preselectYearly() }
        .onChange(of: SubscriptionManager.shared.availableProducts.count) { _, _ in
            preselectYearly()
        }
        .alert(String(localized: "No Purchases Found"), isPresented: $showNoRestoreAlert) {
            Button(String(localized: "OK"), role: .cancel) { }
        } message: {
            Text(String(localized: "We couldn't find any active purchases for this Apple ID. If you believe this is an error, contact support."))
        }
        .alert(String(localized: "Restore Failed"), isPresented: $showRestoreErrorAlert) {
            Button(String(localized: "OK"), role: .cancel) { }
        } message: {
            Text(String(localized: "Restore failed. Please check your connection and try again."))
        }
        .alert(
            String(localized: "Purchase Error"),
            isPresented: Binding(
                get: { purchaseErrorMessage != nil },
                set: { if !$0 { purchaseErrorMessage = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) { }
        } message: {
            if let msg = purchaseErrorMessage {
                Text(msg)
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 14) {
            Image(systemName: "crown.fill")
                .font(.system(size: 54))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.yellow, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.top, 28)
                .accessibilityHidden(true)

            Text("Unlock SHIFT Pro")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("The full power of day-of timeline management")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Feature comparison table

    private var featureTable: some View {
        VStack(spacing: 0) {
            tableHeader
            Divider().padding(.leading, 16)
            tableRow("Active Events",         free: "1",   pro: "Unlimited")
            Divider().padding(.leading, 16)
            tableRow("Blocks per Event",      free: "15",  pro: "Unlimited")
            Divider().padding(.leading, 16)
            tableRow("Vendor Sharing",        free: "✗",   pro: "✓", freeIsNegative: true)
            Divider().padding(.leading, 16)
            tableRow("Widgets & Live Activities", free: "✗", pro: "✓", freeIsNegative: true)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var tableHeader: some View {
        HStack {
            Text("Feature")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Free")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .center)
            Text("Pro")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.accentColor)
                .frame(width: 72, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func tableRow(
        _ feature: String,
        free: String,
        pro: String,
        freeIsNegative: Bool = false
    ) -> some View {
        HStack {
            Text(feature)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(free)
                .font(.subheadline)
                .foregroundStyle(freeIsNegative ? Color.red : Color.primary)
                .frame(width: 72, alignment: .center)
            Text(pro)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(freeIsNegative ? Color.green : Color.primary)
                .frame(width: 72, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Pricing

    private var pricingSection: some View {
        VStack(spacing: 10) {
            if SubscriptionManager.shared.availableProducts.isEmpty {
                ProgressView(String(localized: "Loading plans…"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                if let product = SubscriptionManager.shared.monthlyProduct {
                    pricingCard(product, badge: nil)
                }
                if let product = SubscriptionManager.shared.yearlyProduct {
                    pricingCard(product, badge: yearlySavingsBadge)
                }
                if let product = SubscriptionManager.shared.lifetimeProduct {
                    pricingCard(product, badge: String(localized: "Best Value"))
                }
            }
        }
    }

    private func pricingCard(_ product: Product, badge: String?) -> some View {
        let isSelected = selectedProduct?.id == product.id

        return Button {
            selectedProduct = product
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(product.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        if let badge {
                            Text(badge)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                    }

                    Text(product.displayPrice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                isSelected ? Color.accentColor.opacity(0.08) : Color(.systemBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.secondary.opacity(0.2),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(product.displayName), \(product.displayPrice)\(badge.map { ", \($0)" } ?? "")"
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - CTA

    private var ctaSection: some View {
        Button {
            Task { await purchase() }
        } label: {
            Group {
                if isPurchasing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(ctaLabel)
                        .fontWeight(.bold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(selectedProduct == nil || isPurchasing || isRestoring)
    }

    private var ctaLabel: String {
        guard let product = selectedProduct else {
            return String(localized: "Select a Plan")
        }
        return "\(product.displayName) – \(product.displayPrice)"
    }

    // MARK: - Restore

    private var restoreButton: some View {
        Button {
            Task { await restore() }
        } label: {
            if isRestoring {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text(String(localized: "Restore Purchases"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(isPurchasing || isRestoring)
    }

    // MARK: - Legal

    private var legalText: some View {
        Text(String(localized: "Terms of Use · Privacy Policy"))
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    // MARK: - Logic

    private func preselectYearly() {
        guard selectedProduct == nil,
              let yearly = SubscriptionManager.shared.yearlyProduct else { return }
        selectedProduct = yearly
    }

    private func purchase() async {
        guard let product = selectedProduct else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let didPurchase = try await SubscriptionManager.shared.purchase(product)
            if didPurchase { dismiss() }
            // false == userCancelled/pending: silent no-op per spec
        } catch {
            purchaseErrorMessage = error.localizedDescription
        }
    }

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await SubscriptionManager.shared.restore()
            if SubscriptionManager.shared.isProUser {
                dismiss()
            } else {
                showNoRestoreAlert = true
            }
        } catch {
            showRestoreErrorAlert = true
        }
    }

    private var yearlySavingsBadge: String? {
        guard let monthly = SubscriptionManager.shared.monthlyProduct,
              let yearly = SubscriptionManager.shared.yearlyProduct,
              monthly.price > 0 else { return nil }
        let annualMonthly = monthly.price * 12
        let savings = (annualMonthly - yearly.price) / annualMonthly * 100
        let pct = Int(NSDecimalNumber(decimal: savings).doubleValue.rounded())
        return String(localized: "Save \(pct)%")
    }
}

// MARK: - Previews

#Preview("Event Limit") { PaywallView(trigger: .eventLimit) }
#Preview("Block Limit") { PaywallView(trigger: .blockLimit) }
#Preview("Vendor Sharing") { PaywallView(trigger: .vendorSharing) }
#Preview("Live Activity") { PaywallView(trigger: .liveActivity) }
