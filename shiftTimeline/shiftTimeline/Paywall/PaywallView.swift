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
    /// User tapped "Upgrade to Pro" intentionally from Settings — not a feature gate.
    /// Kept distinct so paywall conversion analytics aren't misattributed to in-app gates.
    case settings

    var id: String { rawValue }

    /// Contextual hero copy that mirrors the call-site reason for presenting the paywall.
    /// Localized via `String(localized:)` so the catalog auto-extracts these strings.
    var heroTitle: String {
        switch self {
        case .eventLimit:    return String(localized: "Plan more than one event")
        case .blockLimit:    return String(localized: "Build longer timelines")
        case .vendorSharing: return String(localized: "Share with your vendors")
        case .liveActivity:  return String(localized: "Stay live on the Lock Screen")
        case .pdfExport:     return String(localized: "Export polished PDFs")
        case .templates:     return String(localized: "Unlock every template")
        case .widgets:       return String(localized: "Add widgets to your Home Screen")
        case .settings:      return String(localized: "Unlock everything in SHIFT")
        }
    }

    var heroSubtitle: String {
        switch self {
        case .eventLimit:
            return String(localized: "The free plan includes one active event. Upgrade to plan as many as you need.")
        case .blockLimit:
            return String(localized: "The free plan caps each event at \(FreeTier.maxBlocksPerEvent) blocks. Pro removes the limit.")
        case .vendorSharing:
            return String(localized: "Send a read-only timeline to photographers, planners, and coordinators.")
        case .liveActivity:
            return String(localized: "Live Activities and Dynamic Island updates are a Pro feature.")
        case .pdfExport:
            return String(localized: "Generate vendor-ready PDF run-of-show documents.")
        case .templates:
            return String(localized: "Get every starter template — wedding, conference, and more.")
        case .widgets:
            return String(localized: "Glance at your active block straight from the Home Screen.")
        case .settings:
            return String(localized: "Unlock unlimited events, vendor sharing, PDF exports, Live Activities, widgets, and every template.")
        }
    }
}

// MARK: - View

struct PaywallView: View {

    /// TODO: Replace with the production marketing site URLs before TestFlight submission.
    private static let termsOfUseURL = URL(string: "https://shift.app/terms")
    private static let privacyPolicyURL = URL(string: "https://shift.app/privacy")

    let trigger: PaywallTrigger

    @Environment(\.dismiss) private var dismiss

    @State private var selectedProduct: Product?
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var showNoRestoreAlert = false
    @State private var showRestoreErrorAlert = false
    @State private var showPendingPurchaseAlert = false
    @State private var purchaseErrorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    heroSection
                    featureTable
                    pricingSection
                    ctaSection
                    autoRenewalDisclosure
                    restoreButton
                    legalLinks
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "SHIFT Pro"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                    .accessibilityLabel(String(localized: "Close"))
                }
            }
        }
        .onAppear {
            preselectYearly()
            AnalyticsService.send(.paywallShown)
        }
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
        .alert(String(localized: "Purchase Pending"), isPresented: $showPendingPurchaseAlert) {
            Button(String(localized: "OK"), role: .cancel) { dismiss() }
        } message: {
            Text(String(localized: "Your purchase is awaiting approval. SHIFT Pro will unlock automatically once it's approved."))
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
            if let errorMessage = purchaseErrorMessage {
                Text(errorMessage)
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

            Text(trigger.heroTitle)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(trigger.heroSubtitle)
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
            tableRow(
                String(localized: "Active Events"),
                free: "\(FreeTier.maxActiveEvents)",
                pro: String(localized: "Unlimited")
            )
            Divider().padding(.leading, 16)
            tableRow(
                String(localized: "Blocks per Event"),
                free: "\(FreeTier.maxBlocksPerEvent)",
                pro: String(localized: "Unlimited")
            )
            Divider().padding(.leading, 16)
            tableRow(
                String(localized: "Vendor Sharing"),
                free: "✗",
                pro: "✓",
                freeIsNegative: true
            )
            Divider().padding(.leading, 16)
            tableRow(
                String(localized: "Widgets & Live Activities"),
                free: "✗",
                pro: "✓",
                freeIsNegative: true
            )
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var tableHeader: some View {
        HStack {
            Text(String(localized: "Feature"))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(localized: "Free"))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .center)
            Text(String(localized: "Pro"))
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

    // MARK: - Auto-renewal disclosure (App Review Guideline 3.1.2)

    @ViewBuilder
    private var autoRenewalDisclosure: some View {
        if let product = selectedProduct, isAutoRenewing(product) {
            Text(String(localized: "Subscriptions automatically renew unless cancelled at least 24 hours before the end of the current period. Manage or cancel anytime in Settings."))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)
        }
    }

    private func isAutoRenewing(_ product: Product) -> Bool {
        product.type == .autoRenewable
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

    @ViewBuilder
    private var legalLinks: some View {
        HStack(spacing: 12) {
            if let url = Self.termsOfUseURL {
                Link(String(localized: "Terms of Use"), destination: url)
            }
            Text("·").foregroundStyle(.tertiary)
            if let url = Self.privacyPolicyURL {
                Link(String(localized: "Privacy Policy"), destination: url)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
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
            let outcome = try await SubscriptionManager.shared.purchase(product)
            switch outcome {
            case .success:
                AnalyticsService.send(.purchaseCompleted, parameters: ["productID": product.id])
                dismiss()
            case .pending:
                showPendingPurchaseAlert = true
            case .userCancelled, .unknown:
                break
            }
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
        let savingsFraction = (annualMonthly - yearly.price) / annualMonthly
        let savingsDouble = NSDecimalNumber(decimal: savingsFraction).doubleValue
        guard savingsDouble > 0 else { return nil }

        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        guard let formatted = formatter.string(from: NSNumber(value: savingsDouble)) else { return nil }
        return String(localized: "Save \(formatted)")
    }
}

// MARK: - Previews

#Preview("Event Limit") { PaywallView(trigger: .eventLimit) }
#Preview("Block Limit") { PaywallView(trigger: .blockLimit) }
#Preview("Vendor Sharing") { PaywallView(trigger: .vendorSharing) }
#Preview("Live Activity") { PaywallView(trigger: .liveActivity) }
