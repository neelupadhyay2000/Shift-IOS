import Models
import SwiftUI

// MARK: - Defaults Keys

/// Centralized `UserDefaults` keys for the Marketplace tab. Keep all `@AppStorage`
/// keys here so a typo can't silently disconnect the teaser from the signup sheet.
///
/// `waitlistJoined` is a local cache of waitlist membership — flipped by the
/// signup sheet (SHIFT-716) after a successful `WaitlistService` upsert; the
/// `marketplace_waitlist` row in Supabase remains the source of truth.
enum MarketplaceDefaultsKey {
    static let waitlistJoined = "marketplaceWaitlistJoined"
}

// MARK: - MarketplaceTeaserView

/// Root view of the Marketplace tab (SHIFT-715) — teases the upcoming vendor
/// marketplace and captures waitlist demand ahead of launch.
///
/// Direction A surfaces throughout: ProBackground canvas, proCard previews,
/// micro-labels for section headers. The vendor cards are hard-coded examples
/// of what a Verified-by-Shift profile will look like, labelled as such; real
/// profiles arrive with marketplace browsing in E10.
struct MarketplaceTeaserView: View {

    @AppStorage(MarketplaceDefaultsKey.waitlistJoined) private var hasJoinedWaitlist = false
    @State private var isPresentingSignup = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                heroSection
                previewSection
                ctaSection
            }
            .padding(20)
            // Readable column on iPad / wide layouts; full width on iPhone.
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background { ProBackground() }
        .navigationTitle(String(localized: "Marketplace"))
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $isPresentingSignup) {
            // SHIFT-716 replaces this placeholder with the waitlist signup
            // sheet (role / category / region) backed by WaitlistService.
            waitlistSignupPlaceholder
        }
    }

    // MARK: Hero

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Find verified vendors. Get found for your work."))
                .font(.title.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(AccessibilityID.Marketplace.heroTitle)
            Text(String(localized: """
            Verified by Shift profiles are built from events actually run in the app — \
            completed events, on-the-day reliability, and reviews from planners who \
            worked alongside the vendor. Not a self-reported resume.
            """))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Preview cards

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "What's coming"))
                .microLabel()
            VStack(spacing: 12) {
                ForEach(VendorPreview.samples) { preview in
                    VendorPreviewCard(preview: preview)
                }
            }
            .accessibilityIdentifier(AccessibilityID.Marketplace.previewCardList)
            Text(String(localized: "Example profiles. Real vendors arrive when the marketplace opens."))
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: CTA / joined state

    @ViewBuilder
    private var ctaSection: some View {
        if hasJoinedWaitlist {
            joinedCard
        } else {
            Button {
                isPresentingSignup = true
            } label: {
                Text(String(localized: "Join the waitlist"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(ShiftPalette.accent)
            .accessibilityIdentifier(AccessibilityID.Marketplace.joinWaitlistButton)
        }
    }

    private var joinedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(String(localized: "You're on the waitlist"))
                    .font(.headline)
            } icon: {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(ShiftPalette.live)
            }
            Text(String(localized: """
            We'll let you know when the marketplace opens. \
            You can update your interests any time.
            """))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(String(localized: "Update interests")) {
                isPresentingSignup = true
            }
            .font(.subheadline.weight(.semibold))
            .tint(ShiftPalette.accent)
            .accessibilityIdentifier(AccessibilityID.Marketplace.updateInterestsButton)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .proCard()
        .accessibilityIdentifier(AccessibilityID.Marketplace.joinedBadge)
    }

    // MARK: Signup placeholder (removed in SHIFT-716)

    private var waitlistSignupPlaceholder: some View {
        NavigationStack {
            ContentUnavailableView(
                String(localized: "Waitlist signup"),
                systemImage: "person.crop.circle.badge.clock",
                description: Text(String(localized: "Coming in the next build."))
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        isPresentingSignup = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - VendorPreviewCard

/// One mocked Verified-by-Shift profile: avatar placeholder, business name,
/// category chip in the role colour, star rating, and the events-via-Shift
/// badge that is the marketplace's core differentiator.
private struct VendorPreviewCard: View {

    let preview: VendorPreview

    private var roleColor: Color { ShiftDesign.roleColor(for: preview.role) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(ShiftPalette.soft(roleColor))
                Image(systemName: "person.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(roleColor)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(preview.businessName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                        Text(preview.rating.formatted(.number.precision(.fractionLength(1))))
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Text(preview.role.displayName)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(ShiftPalette.soft(roleColor), in: Capsule())
                        .foregroundStyle(roleColor)
                    Label {
                        Text(String(localized: "\(preview.eventsViaShift) events via Shift"))
                            .font(.caption)
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                    }
                    .foregroundStyle(ShiftPalette.accent)
                }
            }
        }
        .proCard(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Mocked preview data

/// Hard-coded example vendors for the teaser cards. Purely illustrative;
/// replaced by real marketplace profiles in E10.
private struct VendorPreview: Identifiable {
    let id: String
    let businessName: String
    let role: VendorRole
    let rating: Double
    let eventsViaShift: Int

    static let samples: [VendorPreview] = [
        VendorPreview(
            id: "golden-hour", businessName: "Golden Hour Studios",
            role: .photographer, rating: 4.9, eventsViaShift: 12
        ),
        VendorPreview(
            id: "atlas-sound", businessName: "Atlas Sound Co.",
            role: .dj, rating: 4.8, eventsViaShift: 9
        ),
        VendorPreview(
            id: "stem-petal", businessName: "Stem & Petal Floral",
            role: .florist, rating: 5.0, eventsViaShift: 17
        ),
    ]
}

// MARK: - Previews

#Preview("Teaser — light") {
    NavigationStack {
        MarketplaceTeaserView()
    }
}

#Preview("Teaser — dark") {
    NavigationStack {
        MarketplaceTeaserView()
    }
    .preferredColorScheme(.dark)
}

#Preview("Joined state") {
    let defaults = UserDefaults(suiteName: "marketplace-teaser-preview") ?? .standard
    defaults.set(true, forKey: MarketplaceDefaultsKey.waitlistJoined)
    return NavigationStack {
        MarketplaceTeaserView()
    }
    .defaultAppStorage(defaults)
}
