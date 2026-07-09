import SwiftUI

// MARK: - Eligibility

/// Pure gate for the one-time vendor opt-in suggestion (E24 Task 2): a user who
/// has claimed ≥1 vendor invite (they've *worked* events on Shift) but has no
/// vendor profile is the highest-value supply to convert — their claimed events
/// already count as verified marketplace history.
enum VendorOptInPrompt {
    static let shownDefaultsKey = "vendorOptInPromptShown"

    /// Whether the prompt should be presented. One-shot: `alreadyShown` wins
    /// over everything, so the user is asked exactly once per install.
    static func isEligible(
        workedEventCount: Int,
        hasVendorProfile: Bool,
        isVendorAccount: Bool,
        alreadyShown: Bool
    ) -> Bool {
        !alreadyShown && !isVendorAccount && !hasVendorProfile && workedEventCount >= 1
    }

    /// "You've worked 3 events on Shift." — singular-safe.
    static func headline(workedEventCount: Int) -> String {
        if workedEventCount == 1 {
            return String(localized: "You've worked 1 event on Shift")
        }
        return String(localized: "You've worked \(workedEventCount) events on Shift")
    }
}

// MARK: - Sheet

/// One-time opt-in sheet shown at the app root. The CTA deep-links into the
/// become-a-vendor flow (Settings → vendor settings, which handles the
/// planner→vendor account switch); declining just dismisses — the marketplace
/// home's "become a vendor" nudge remains as the evergreen path.
struct VendorOptInPromptView: View {

    let workedEventCount: Int
    let onCreateProfile: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)

            ShiftIconTile(systemImage: "checkmark.seal.fill")
                .scaleEffect(1.6)
                .padding(.bottom, 8)

            VStack(spacing: 10) {
                Text(VendorOptInPrompt.headline(workedEventCount: workedEventCount))
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(String(localized: """
                Create your vendor profile and every event you've worked counts \
                as verified history — planners see real experience, not claims.
                """))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button {
                    AnalyticsService.send(.marketplaceVendorOptInAccepted, parameters: [
                        "workedEvents": "\(workedEventCount)",
                    ])
                    onCreateProfile()
                    dismiss()
                } label: {
                    Text(String(localized: "Create Vendor Profile"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(ShiftPalette.accent)

                Button {
                    dismiss()
                } label: {
                    Text(String(localized: "Not Now"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .background { ProBackground() }
        .accessibilityIdentifier(AccessibilityID.Marketplace.vendorOptInPrompt)
    }
}
