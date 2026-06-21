import Models
import SwiftUI

/// A vendor's public marketplace profile: identity header, "Verified by Shift"
/// stats, the portfolio grid (photos + verified event cards), and the
/// report/block safety menu. The "Request for an event…" action is a stub until
/// E11 ships the request flow.
struct VendorPublicProfileView: View {

    let profileID: UUID

    @Environment(\.marketplaceService) private var service
    @Environment(\.vendorReviewService) private var reviewService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var profile: MarketplaceVendorProfile?
    @State private var portfolio: [PortfolioItemDTO] = []
    @State private var eventSummaries: [UUID: PortfolioEventSummaryDTO] = [:]
    @State private var stats: VendorPublicStatsDTO?
    @State private var reviews: [VendorReviewDTO] = []
    @State private var canLoadMoreReviews = true
    @State private var isLoadingMoreReviews = false
    @State private var isLoading = true
    @State private var isPresentingComposer = false

    private let reviewPageSize = 20

    private var title: String {
        if let name = profile?.identity.businessName, !name.isEmpty { return name }
        if let display = profile?.identity.displayName, !display.isEmpty { return display }
        return String(localized: "Vendor")
    }

    var body: some View {
        ScrollView {
            if isLoading, profile == nil {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 80)
            } else if let profile {
                content(profile)
            } else {
                ContentUnavailableView(
                    String(localized: "Profile unavailable"),
                    systemImage: "person.crop.square.badge.questionmark",
                    description: Text(String(localized: "This vendor isn't listed in the marketplace."))
                )
                .padding(.top, 60)
            }
        }
        .background { ProBackground() }
        .navigationTitle(String(localized: "Vendor"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                VendorSafetyMenu(
                    subjectProfileID: profileID,
                    subjectName: title,
                    contentType: .vendorProfile,
                    onBlocked: { dismiss() }
                )
            }
        }
        .task { await load() }
        .sheet(isPresented: $isPresentingComposer) {
            RequestComposerView(vendorProfileID: profileID, vendorName: title)
        }
    }

    // MARK: Content

    private func content(_ profile: MarketplaceVendorProfile) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            header(profile)
            requestButton
            statsRow(profile.vendor)
            if !profile.identity.bio.isNilOrEmpty { bioSection(profile.identity.bio ?? "") }
            portfolioSection
            reviewsSection
        }
        .padding(20)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }

    private func header(_ profile: MarketplaceVendorProfile) -> some View {
        VStack(spacing: 12) {
            VendorAvatar(urlString: profile.identity.avatarURL, category: profile.vendor.category, size: 88)
            Text(title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            if let avg = profile.vendor.ratingAvg, profile.vendor.ratingCount > 0 {
                aggregateRating(avg: avg, count: profile.vendor.ratingCount)
            }
            CategoryChip(category: profile.vendor.category)
            if let area = profile.vendor.serviceArea, !area.isEmpty {
                Label(area, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !profile.vendor.skills.isEmpty {
                skillChips(profile.vendor.skills)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier(AccessibilityID.Marketplace.profileHeader)
    }

    private func skillChips(_ skills: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(skills, id: \.self) { skill in
                    Text(skill.capitalized)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(ShiftPalette.soft(ShiftPalette.neutral), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: Verified-by-Shift stats

    private func statsRow(_ vendor: VendorProfileDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(localized: "Verified by Shift"), systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ShiftPalette.accent)
            HStack(spacing: 0) {
                statCell(
                    value: "\(stats?.eventsCompleted ?? vendor.eventsCompletedCount)",
                    label: String(localized: "Events completed")
                )
                Divider().frame(height: 36)
                statCell(
                    value: vendor.ratingAvg.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—",
                    label: vendor.ratingCount > 0
                        ? String(localized: "\(vendor.ratingCount) ratings")
                        : String(localized: "Rating")
                )
                if let reliability = stats?.reliabilityPct {
                    Divider().frame(height: 36)
                    statCell(
                        value: "\(reliability)%",
                        label: String(localized: "On-time finish")
                    )
                }
            }
            if let repeatCount = stats?.repeatPlannerCount, repeatCount > 0 {
                Label(
                    String(localized: "\(repeatCount) repeat \(repeatCount == 1 ? "planner" : "planners")"),
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .proCard()
    }

    /// Compact header rating: a star, the average, and the count.
    private func aggregateRating(avg: Double, count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill").foregroundStyle(ShiftPalette.accent)
            Text(avg.formatted(.number.precision(.fractionLength(1))))
                .font(.subheadline.weight(.semibold))
            Text("(\(count))").font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Rated \(avg.formatted(.number.precision(.fractionLength(1)))) from \(count) reviews"))
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.weight(.bold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func bioSection(_ bio: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "About")).microLabel()
            Text(bio)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Request CTA (stub until E11)

    private var requestButton: some View {
        Button {
            isPresentingComposer = true
        } label: {
            Label(String(localized: "Request for an event…"), systemImage: "paperplane.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(ShiftPalette.accent.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.pressableCard)
        .accessibilityIdentifier(AccessibilityID.Marketplace.requestButton)
    }

    // MARK: Portfolio

    private var portfolioColumns: [GridItem] {
        let minimum: CGFloat = sizeClass == .regular ? 150 : 110
        return [GridItem(.adaptive(minimum: minimum), spacing: 10)]
    }

    @ViewBuilder
    private var portfolioSection: some View {
        if !portfolio.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "Portfolio")).microLabel()
                LazyVGrid(columns: portfolioColumns, spacing: 10) {
                    ForEach(portfolio) { item in
                        portfolioTile(item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func portfolioTile(_ item: PortfolioItemDTO) -> some View {
        if item.kind == "shift_event" {
            verifiedEventTile(item)
        } else if let path = item.storagePath, let url = service?.portfolioImageURL(forPath: path) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ProgressView()
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: ShiftDesign.cardRadius, style: .continuous))
        }
    }

    private func verifiedEventTile(_ item: PortfolioItemDTO) -> some View {
        let summary = item.eventID.flatMap { eventSummaries[$0] }
        return VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(ShiftPalette.accent)
            Text(summary?.title ?? item.caption ?? String(localized: "Event"))
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            if let date = summary?.eventDate.value {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .aspectRatio(1, contentMode: .fill)
        .proCard(padding: 12)
    }

    // MARK: Reviews

    @ViewBuilder
    private var reviewsSection: some View {
        if !reviews.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "Reviews")).microLabel()
                ForEach(reviews) { review in
                    reviewCard(review)
                }
                if canLoadMoreReviews {
                    Button {
                        Task { await loadMoreReviews() }
                    } label: {
                        if isLoadingMoreReviews {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text(String(localized: "Show more reviews"))
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoadingMoreReviews)
                }
            }
            .accessibilityIdentifier(AccessibilityID.Marketplace.reviewsList)
        }
    }

    private func reviewCard(_ review: VendorReviewDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(review.reviewerName).font(.subheadline.weight(.semibold))
                    starsRow(review.rating)
                }
                Spacer()
                // UGC safety: report/block the review's author (Apple 1.2).
                VendorSafetyMenu(
                    subjectProfileID: review.reviewerID,
                    subjectName: review.reviewerName,
                    contentType: .review,
                    contentID: review.id
                )
            }
            if !review.body.isEmpty {
                Text(review.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let footer = eventFooter(title: review.eventTitle, date: review.eventDate?.value) {
                Text(footer)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .proCard(padding: 14)
    }

    /// "Event Title · Jan 1, 2026", omitting whichever part is missing.
    private func eventFooter(title: String?, date: Date?) -> String? {
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let dateText = date.map { $0.formatted(date: .abbreviated, time: .omitted) }
        let parts = [name?.isEmpty == false ? name : nil, dateText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func starsRow(_ rating: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.caption2)
                    .foregroundStyle(star <= rating ? ShiftPalette.accent : .secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(rating) out of 5 stars"))
    }

    // MARK: Data

    private func load() async {
        guard let service else { isLoading = false; return }
        isLoading = true
        defer { isLoading = false }
        profile = try? await service.fetchVendorProfile(profileID: profileID)
        guard profile != nil else { return }
        portfolio = (try? await service.portfolioItems(profileID: profileID)) ?? []
        let summaries = (try? await service.portfolioEventSummaries(profileID: profileID)) ?? []
        eventSummaries = Dictionary(summaries.map { ($0.eventID, $0) }, uniquingKeysWith: { first, _ in first })

        // Verified stats + first page of reviews (best-effort; nil service = no-op).
        if let reviewService {
            stats = try? await reviewService.stats(profileID: profileID)
        }
        reviews = []
        canLoadMoreReviews = true
        await loadMoreReviews()
    }

    private func loadMoreReviews() async {
        guard let reviewService, canLoadMoreReviews, !isLoadingMoreReviews else { return }
        isLoadingMoreReviews = true
        defer { isLoadingMoreReviews = false }
        let page = (try? await reviewService.reviews(
            vendorProfileID: profileID, limit: reviewPageSize, offset: reviews.count
        )) ?? []
        reviews.append(contentsOf: page)
        canLoadMoreReviews = page.count == reviewPageSize
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool { self?.isEmpty ?? true }
}
