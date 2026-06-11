import Services
import StoreKit
import SwiftUI

/// Launch interstitial for free users: one rotating "something cool about
/// Shift" fact, a compact Pro pitch, and a purchase CTA into the full paywall.
/// Deliberately has no tap-outside or swipe dismissal — the small ✕ at the top
/// right is the only way out.
struct LaunchPromoView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingPaywall = false

    private let fact = LaunchFact.pick()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 48)
                    factSection
                    proCardSection
                    ctaSection
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }

            closeButton
        }
        .background { ProBackground() }
        .interactiveDismissDisabled()
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView(trigger: .launchPromo)
        }
        .onAppear {
            AnalyticsService.send(.launchPromoShown, parameters: ["fact": fact.id])
        }
        // Purchasing (or restoring) from the embedded paywall makes the promo moot.
        .onChange(of: SubscriptionManager.shared.isProUser) { _, isPro in
            if isPro { dismiss() }
        }
    }

    // MARK: - Close (the only exit)

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(.thinMaterial, in: Circle())
        }
        .padding(.top, 16)
        .padding(.trailing, 20)
        .accessibilityLabel(String(localized: "Close"))
        .accessibilityIdentifier(AccessibilityID.LaunchPromo.closeButton)
    }

    // MARK: - Rotating fact

    private var factSection: some View {
        VStack(spacing: 14) {
            Image(systemName: fact.icon)
                .font(.system(size: 44))
                .foregroundStyle(ShiftPalette.accent)
                .accessibilityHidden(true)

            Text(String(localized: "Did you know?")).microLabel()

            Text(fact.title)
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(fact.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Pro pitch

    private var proCardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(String(localized: "SHIFT Pro"))
                    .font(.headline)
            } icon: {
                Image(systemName: "crown.fill")
                    .foregroundStyle(.yellow)
            }

            proFeatureRow(
                icon: "calendar.badge.plus",
                text: String(localized: "Unlimited events and blocks")
            )
            proFeatureRow(
                icon: "square.and.arrow.up",
                text: String(localized: "Live read-only timelines for your vendors")
            )
            proFeatureRow(
                icon: "platter.filled.top.iphone",
                text: String(localized: "Widgets, Live Activities, and PDF run sheets")
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .proCard()
    }

    private func proFeatureRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ShiftPalette.accent)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: 10) {
            Button {
                isShowingPaywall = true
            } label: {
                Text(ctaLabel)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(ShiftPalette.accent)
            .accessibilityIdentifier(AccessibilityID.LaunchPromo.upgradeButton)

            Text(String(localized: "Cancel anytime. The free plan stays free."))
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    private var ctaLabel: String {
        if let yearly = SubscriptionManager.shared.yearlyProduct {
            return String(localized: "Try SHIFT Pro — from \(yearly.displayPrice)/year")
        }
        return String(localized: "See SHIFT Pro plans")
    }
}

// MARK: - Launch facts

/// Rotating launch-screen facts — each highlights one piece of what makes
/// Shift different. One is picked at random per showing.
private struct LaunchFact: Identifiable {
    let id: String
    let icon: String
    let title: String
    let detail: String

    static func pick() -> LaunchFact {
        all.randomElement() ?? all[0]
    }

    static let all: [LaunchFact] = [
        LaunchFact(
            id: "ripple",
            icon: "clock.arrow.circlepath",
            title: String(localized: "One tap reshuffles your whole day."),
            detail: String(localized: """
            When an event runs late, the Ripple Engine shifts every downstream \
            block and compresses what no longer fits — in under 50 milliseconds.
            """)
        ),
        LaunchFact(
            id: "offline",
            icon: "antenna.radiowaves.left.and.right.slash",
            title: String(localized: "Built for venues with zero signal."),
            detail: String(localized: """
            Every change works fully offline and syncs the moment you're back \
            online — barns, basements, and ballrooms included.
            """)
        ),
        LaunchFact(
            id: "goldenHour",
            icon: "sun.horizon.fill",
            title: String(localized: "Never miss golden hour again."),
            detail: String(localized: """
            Shift tracks sunset and golden hour for your venue and reminds you \
            30 minutes before the light gets good.
            """)
        ),
        LaunchFact(
            id: "vendors",
            icon: "person.2.wave.2.fill",
            title: String(localized: "Your vendors see shifts the moment they happen."),
            detail: String(localized: """
            Share a live, read-only timeline — vendors get notified when plans \
            move and confirm with one tap.
            """)
        ),
    ]
}

// MARK: - Previews

#Preview("Launch promo — light") {
    LaunchPromoView()
}

#Preview("Launch promo — dark") {
    LaunchPromoView()
        .preferredColorScheme(.dark)
}
