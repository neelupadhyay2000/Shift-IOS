import Models
import SwiftUI

// MARK: - Eligibility

/// Pure gate for the post-event seeding prompt (E24 Task 2): shown to the event
/// owner on a completed event that still has vendors who never claimed a Shift
/// profile — the supply-side flywheel moment ("your photographer just worked
/// this event; invite them while it's fresh").
enum PostEventInvitePrompt {

    /// Vendors on the event who have no linked profile (never claimed an invite).
    /// These are exactly the people worth converting into marketplace supply.
    static func unclaimedVendors(_ vendors: [VendorModel]) -> [VendorModel] {
        vendors.filter { $0.profileId == nil }
    }

    /// Whether the prompt card should render.
    static func isEligible(
        isCompleted: Bool,
        isOwner: Bool,
        unclaimedCount: Int,
        isDismissed: Bool
    ) -> Bool {
        isCompleted && isOwner && unclaimedCount > 0 && !isDismissed
    }

    /// Personalized headline: a single unclaimed vendor is addressed by role
    /// ("Invite your photographer…"); several fall back to the plural form.
    static func headline(for unclaimed: [VendorModel]) -> String {
        if unclaimed.count == 1, let vendor = unclaimed.first {
            return String(localized: "Invite your \(vendor.role.displayName.lowercased()) to claim their Shift profile")
        }
        return String(localized: "Invite your vendors to claim their Shift profiles")
    }
}

// MARK: - Dismissal store

/// Per-event, forever dismissal for the seeding prompt — a plain UserDefaults
/// string-set so declining once doesn't nag on every visit to the event.
/// Injectable defaults keep tests isolated from the real domain.
struct PostEventInvitePromptStore {
    private let defaults: UserDefaults
    private let key = "postEventInvitePromptDismissed"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isDismissed(eventID: UUID) -> Bool {
        let dismissed = defaults.stringArray(forKey: key) ?? []
        return dismissed.contains(eventID.uuidString)
    }

    func dismiss(eventID: UUID) {
        var dismissed = defaults.stringArray(forKey: key) ?? []
        guard !dismissed.contains(eventID.uuidString) else { return }
        dismissed.append(eventID.uuidString)
        defaults.set(dismissed, forKey: key)
    }
}

// MARK: - Shown-signal session guard

/// Dedupes the `marketplace.seedInviteShown` signal to once per event per app
/// session — detail views re-render constantly, and the funnel needs prompt
/// reach, not render counts. (Same pattern as `CommunityTeaserSignalGuard`.)
@MainActor
enum SeedInviteSignalGuard {
    static var fired: Set<UUID> = []
}

// MARK: - Card

/// The prompt card shown on a completed event's detail page. The CTA hands off
/// to the existing invite flow (`VendorSharingView` via the caller — identity-
/// locked links, App Store fallback); this card is only the flywheel nudge.
struct PostEventInvitePromptCard: View {

    let unclaimed: [VendorModel]
    let onInvite: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ShiftIconTile(systemImage: "person.crop.circle.badge.plus")
            VStack(alignment: .leading, spacing: 4) {
                Text(PostEventInvitePrompt.headline(for: unclaimed))
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(localized: """
                They worked this event — once they claim their profile, it counts \
                as verified history on the Shift Marketplace.
                """))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onInvite) {
                    Text(String(localized: "Invite"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(ShiftPalette.accent, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Dismiss"))
        }
        .proCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Events.postEventInvitePrompt)
    }
}
