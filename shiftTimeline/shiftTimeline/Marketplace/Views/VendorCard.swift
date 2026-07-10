import Models
import SwiftUI

// MARK: - Category resolution
//
// The stored `category` is a VendorRole raw value, or a free-text label for the
// custom role. These helpers resolve a stored string to its display label and
// role colour (unknown → custom), shared across the directory surfaces.
enum MarketplaceCategory {
    static func role(_ raw: String) -> VendorRole { VendorRole(rawValue: raw) ?? .custom }

    static func label(_ raw: String) -> String {
        VendorRole(rawValue: raw)?.displayName ?? raw
    }

    static func color(_ raw: String) -> Color {
        ShiftDesign.roleColor(for: role(raw))
    }
}

// MARK: - Category chip

/// Small role-coloured capsule used for a vendor's category.
struct CategoryChip: View {
    let category: String
    var compact = false

    var body: some View {
        let color = MarketplaceCategory.color(category)
        HStack(spacing: 4) {
            Image(systemName: MarketplaceCategory.role(category).systemImage)
                .font(.caption2)
            Text(MarketplaceCategory.label(category))
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, compact ? 7 : 9)
        .padding(.vertical, compact ? 3 : 4)
        .foregroundStyle(color)
        .background(ShiftPalette.soft(color), in: Capsule())
    }
}

// MARK: - Avatar

/// Circular vendor avatar: async image when available, else a role-tinted glyph.
struct VendorAvatar: View {
    let urlString: String?
    let category: String
    var size: CGFloat = 48

    var body: some View {
        let color = MarketplaceCategory.color(category)
        ZStack {
            Circle().fill(ShiftPalette.soft(color))
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ProgressView()
                }
                .clipShape(Circle())
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Stats badges

/// "Verified by Shift" events-completed badge + star rating. Until E13 populates
/// the stats, a vendor with no completed events reads as "New to Shift".
struct VendorStatsBadges: View {
    let eventsCompleted: Int
    let ratingAvg: Double?
    let ratingCount: Int

    var body: some View {
        HStack(spacing: 8) {
            if eventsCompleted > 0 {
                Label {
                    Text("\(eventsCompleted) events via Shift")
                        .font(.caption2.weight(.medium))
                } icon: {
                    Image(systemName: "checkmark.seal.fill").font(.caption2)
                }
                .foregroundStyle(ShiftPalette.accent)
            } else {
                Text(String(localized: "New to Shift"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if let ratingAvg, ratingCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill").font(.caption2)
                    Text(ratingAvg.formatted(.number.precision(.fractionLength(1))))
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(ShiftPalette.warm)
            }
        }
    }
}

// MARK: - Vendor card

/// How a `VendorCard` is being laid out. The two directory surfaces want the same
/// card with different proportions: a wide, short hero in a horizontal carousel,
/// and a square, dense hero in the browse grid.
enum VendorCardStyle {
    /// Home carousels — fixed-height hero, roomier meta.
    case carousel
    /// Facebook-Marketplace-style browse grid — square hero, compact meta.
    case grid
}

/// Directory card for a vendor.
///
/// The hero is the vendor's **work** — their first portfolio photo/video
/// (`cover_path`), not their face. That's the whole point: for event vendors the
/// portfolio *is* the product. The avatar is demoted to a small circular
/// attribution mark beside the name, the way an Instagram post credits its author.
/// Falls back to the avatar, then to a role-tinted gradient, when a vendor has no
/// portfolio yet.
///
/// The **service** is promoted onto the image as a coloured chip, so a planner
/// scanning a grid can tell a photographer from a florist without reading.
struct VendorCard: View {
    let result: VendorSearchResultDTO
    /// Planner-only save affordance; nil hides the heart (e.g. vendor viewers).
    var isSaved: Bool = false
    var onToggleSave: (() -> Void)?
    var style: VendorCardStyle = .carousel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.marketplaceService) private var service

    private var cardFill: Color { colorScheme == .dark ? .white.opacity(0.055) : .white }
    private var hairline: Color { colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.07) }
    private var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: ShiftDesign.cardRadius, style: .continuous) }

    private var title: String {
        if let name = result.businessName, !name.isEmpty { return name }
        if !result.displayName.isEmpty { return result.displayName }
        return String(localized: "Vendor")
    }

    private var color: Color { MarketplaceCategory.color(result.category) }
    private var isGrid: Bool { style == .grid }

    /// The vendor's own first portfolio item, resolved to a CDN URL.
    private var coverURL: URL? {
        guard let path = result.coverPath else { return nil }
        return service?.portfolioImageURL(forPath: path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            meta
        }
        .background(cardFill, in: cardShape)
        .clipShape(cardShape)
        .overlay(cardShape.strokeBorder(hairline, lineWidth: 1))
        .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.05), radius: 8, y: 3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityIdentifier(AccessibilityID.Marketplace.vendorCard)
    }

    // MARK: Hero — the vendor's work

    @ViewBuilder
    private var heroContent: some View {
        if let coverURL {
            if result.coverIsVideo {
                VideoThumbnailView(url: coverURL, playGlyphSize: isGrid ? .title3 : .title)
            } else {
                AsyncImage(url: coverURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    LinearGradient(colors: [ShiftPalette.soft(color), color.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
        } else if let urlString = result.avatarURL, let url = URL(string: urlString) {
            // No portfolio yet — fall back to their profile photo.
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                LinearGradient(colors: [ShiftPalette.soft(color), color.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        } else {
            ZStack {
                LinearGradient(colors: [ShiftPalette.soft(color), color.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: MarketplaceCategory.role(result.category).systemImage)
                    .font(.system(size: isGrid ? 32 : 40)).foregroundStyle(color.opacity(0.7))
            }
        }
    }

    @ViewBuilder
    private var hero: some View {
        let content = ZStack { heroContent }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topLeading) { ratingPill }
            .overlay(alignment: .topTrailing) { if onToggleSave != nil { saveButton } }
            // The service, promoted onto the image so it's readable at a glance.
            .overlay(alignment: .bottomLeading) {
                CategoryChip(category: result.category, compact: isGrid)
                    .padding(10)
            }

        if isGrid {
            // `.fit`, not `.fill`. On a *view* (unlike on an Image), `.fill` sizes
            // to the larger dimension of the proposal, and the proposal's height
            // resolves to the cover photo's ideal height — so a portrait poster
            // produced a square as tall as the photo and the cell spilled out of
            // its grid column on both sides. `.fit` takes the smaller dimension,
            // which is the column width. The inner `scaledToFill()` still fills
            // that square; `.clipped()` crops the overflow.
            content.aspectRatio(1, contentMode: .fit).clipped()
        } else {
            content.frame(height: 150).clipped()
        }
    }

    // MARK: Meta

    private var meta: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                VendorAvatar(urlString: result.avatarURL, category: result.category, size: isGrid ? 22 : 26)
                Text(title)
                    .font(isGrid ? .subheadline.weight(.semibold) : .headline)
                    .lineLimit(1)
            }

            locationLine

            VendorStatsBadges(
                eventsCompleted: result.eventsCompletedCount,
                ratingAvg: result.ratingAvg,
                ratingCount: result.ratingCount
            )
            .lineLimit(1)
        }
        .padding(isGrid ? 10 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Distance wins when we have the caller's location; otherwise the vendor's
    /// own service-area text.
    @ViewBuilder
    private var locationLine: some View {
        if let km = result.distanceKm {
            Label(VendorDistance.label(km: km), systemImage: "location.fill")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        } else if let area = result.serviceArea, !area.isEmpty {
            Label(area, systemImage: "mappin.and.ellipse")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    // MARK: Overlays

    @ViewBuilder
    private var ratingPill: some View {
        if let avg = result.ratingAvg, result.ratingCount > 0 {
            HStack(spacing: 3) {
                Image(systemName: "star.fill").font(.caption2)
                Text(avg.formatted(.number.precision(.fractionLength(1)))).font(.caption2.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(10)
        }
    }

    private var saveButton: some View {
        Button { onToggleSave?() } label: {
            Image(systemName: isSaved ? "heart.fill" : "heart")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSaved ? ShiftPalette.accent : .white)
                .padding(8)
                .background(.black.opacity(0.4), in: Circle())
                .padding(10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSaved ? String(localized: "Unsave vendor") : String(localized: "Save vendor"))
        .accessibilityIdentifier(AccessibilityID.Marketplace.saveVendorButton)
    }

    /// One spoken sentence instead of a pile of fragments.
    private var accessibilityDescription: String {
        var parts = [title, MarketplaceCategory.label(result.category)]
        if let km = result.distanceKm { parts.append(VendorDistance.label(km: km)) }
        else if let area = result.serviceArea, !area.isEmpty { parts.append(area) }
        if let avg = result.ratingAvg, result.ratingCount > 0 {
            parts.append(String(localized: "rated \(avg.formatted(.number.precision(.fractionLength(1)))) from \(result.ratingCount) reviews"))
        }
        return parts.joined(separator: ", ")
    }
}
