import SwiftUI

/// Vendor "home" dashboard (E22) shown atop the Marketplace tab for vendor
/// accounts: verified stats at a glance, a profile-strength nudge, the requests
/// inbox CTA, an availability summary, and listing status. Makes the vendor side
/// feel like a real pro tool rather than a list.
struct VendorDashboardView: View {

    /// Opens the Settings vendor area (profile / availability / listing).
    var onOpenVendorSettings: () -> Void

    @Environment(\.marketplaceService) private var marketplace
    @Environment(\.vendorReviewService) private var reviews
    @Environment(\.serviceRequestService) private var requests
    @Environment(\.availabilityService) private var availability
    @Environment(SupabaseAuthService.self) private var authService

    @State private var profile: MarketplaceVendorProfile?
    @State private var stats: VendorPublicStatsDTO?
    @State private var pendingCount = 0
    @State private var portfolioCount = 0
    @State private var busyThisMonth = 0
    @State private var isLoading = true

    private var businessName: String {
        profile?.identity.businessName?.nilIfEmpty ?? profile?.identity.displayName.nilIfEmpty ?? String(localized: "Your vendor profile")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if isLoading {
                SkeletonBlock(height: 96, cornerRadius: ShiftDesign.cardRadius)
            } else {
                statsHero
                if strength.fraction < 1 { profileStrength }
                quickActions
            }
        }
        .task { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "Welcome back")).microLabel()
            Text(businessName).font(.title2.weight(.bold)).lineLimit(1)
        }
    }

    // MARK: Stats hero

    private var statsHero: some View {
        HStack(spacing: 0) {
            statCell(value: ratingText, label: String(localized: "Rating"), icon: "star.fill")
            divider
            statCell(value: "\(stats?.eventsCompleted ?? profile?.vendor.eventsCompletedCount ?? 0)", label: String(localized: "Events"), icon: "checkmark.seal.fill")
            divider
            statCell(value: reliabilityText, label: String(localized: "On-time"), icon: "clock.badge.checkmark")
            divider
            statCell(value: "\(stats?.repeatPlannerCount ?? 0)", label: String(localized: "Repeat"), icon: "arrow.triangle.2.circlepath")
        }
        .proCard(padding: 14)
    }

    private var divider: some View { Divider().frame(height: 34) }

    private func statCell(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.caption2).foregroundStyle(ShiftPalette.accent)
            Text(value).font(.headline).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var ratingText: String {
        guard let avg = profile?.vendor.ratingAvg, (profile?.vendor.ratingCount ?? 0) > 0 else { return "—" }
        return avg.formatted(.number.precision(.fractionLength(1)))
    }

    private var reliabilityText: String {
        stats?.reliabilityPct.map { "\($0)%" } ?? "—"
    }

    // MARK: Profile strength

    private struct Strength { let filled: Int; let total: Int; var fraction: Double { total == 0 ? 1 : Double(filled) / Double(total) } }

    private var strength: Strength {
        guard let p = profile else { return Strength(filled: 0, total: 5) }
        let checks = [
            !(p.identity.avatarURL ?? "").isEmpty,
            !(p.identity.bio ?? "").isEmpty,
            !p.vendor.skills.isEmpty,
            !(p.vendor.serviceArea ?? "").isEmpty,
            portfolioCount > 0,
        ]
        return Strength(filled: checks.filter { $0 }.count, total: checks.count)
    }

    private var profileStrength: some View {
        Button { onOpenVendorSettings() } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(String(localized: "Profile strength"), systemImage: "person.crop.circle.badge.checkmark")
                        .font(.caption.weight(.semibold)).foregroundStyle(ShiftPalette.accent)
                    Spacer()
                    Text("\(Int(strength.fraction * 100))%").font(.caption.weight(.bold)).monospacedDigit()
                }
                ProgressView(value: strength.fraction).tint(ShiftPalette.accent)
                Text(nextStrengthTip).font(.caption2).foregroundStyle(.secondary)
            }
            .proCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
    }

    private var nextStrengthTip: String {
        guard let p = profile else { return String(localized: "Complete your profile to rank higher.") }
        if (p.identity.avatarURL ?? "").isEmpty { return String(localized: "Add a profile photo to stand out.") }
        if portfolioCount == 0 { return String(localized: "Add portfolio photos to win more bookings.") }
        if (p.identity.bio ?? "").isEmpty { return String(localized: "Add a short bio about your work.") }
        if p.vendor.skills.isEmpty { return String(localized: "Add skills so planners can find you.") }
        if (p.vendor.serviceArea ?? "").isEmpty { return String(localized: "Add your service area.") }
        return String(localized: "Tap to polish your profile.")
    }

    // MARK: Quick actions

    private var quickActions: some View {
        VStack(spacing: 12) {
            NavigationLink(value: MarketplaceDestination.inbox) {
                actionRow(
                    icon: "tray.full.fill",
                    title: String(localized: "Event requests"),
                    subtitle: pendingCount > 0 ? String(localized: "\(pendingCount) awaiting your response") : String(localized: "Requests & messages"),
                    badge: pendingCount > 0 ? "\(pendingCount)" : nil
                )
            }
            .buttonStyle(.pressableCard)
            .accessibilityIdentifier(AccessibilityID.Marketplace.inbox)

            Button { onOpenVendorSettings() } label: {
                actionRow(
                    icon: (profile?.vendor.isListed ?? false) ? "checkmark.seal.fill" : "eye.slash.fill",
                    title: (profile?.vendor.isListed ?? false) ? String(localized: "Listed in the marketplace") : String(localized: "Hidden from the marketplace"),
                    subtitle: busyThisMonth > 0 ? String(localized: "\(busyThisMonth) busy days this month · manage") : String(localized: "Profile, availability & visibility"),
                    badge: nil
                )
            }
            .buttonStyle(.pressableCard)
        }
    }

    private func actionRow(icon: String, title: String, subtitle: String, badge: String?) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(ShiftPalette.accent)
                .frame(width: 36, height: 36)
                .background(ShiftPalette.soft(ShiftPalette.accent), in: RoundedRectangle(cornerRadius: ShiftDesign.iconRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let badge {
                Text(badge).font(.caption.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.red, in: Capsule())
            }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .proCard()
        .contentShape(Rectangle())
    }

    // MARK: Data

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let myID = authService.currentProfileID else { return }
        if let marketplace {
            profile = try? await marketplace.fetchVendorProfile(profileID: myID)
            portfolioCount = ((try? await marketplace.portfolioItems(profileID: myID)) ?? []).count
        }
        if let reviews { stats = try? await reviews.stats(profileID: myID) }
        if let requests {
            let inbox = (try? await requests.inbox(limit: 100, offset: 0)) ?? []
            pendingCount = inbox.filter { $0.status == ServiceRequestStatus.pending.rawValue }.count
        }
        if let availability {
            let (from, to) = Self.monthBounds()
            let days = (try? await availability.calendar(from: from, to: to)) ?? []
            // Distinct busy days this month (manual + booked).
            busyThisMonth = Set(days.map(\.busyDate)).count
        }
    }

    private static func monthBounds() -> (Date, Date) {
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? now
        return (start, end)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
