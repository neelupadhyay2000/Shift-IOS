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

/// Directory list/grid card for a single vendor search result.
struct VendorCard: View {
    let result: VendorSearchResultDTO

    private var title: String {
        if let name = result.businessName, !name.isEmpty { return name }
        if !result.displayName.isEmpty { return result.displayName }
        return String(localized: "Vendor")
    }

    var body: some View {
        HStack(spacing: 12) {
            VendorAvatar(urlString: result.avatarURL, category: result.category)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    CategoryChip(category: result.category, compact: true)
                    if let area = result.serviceArea, !area.isEmpty {
                        Label(area, systemImage: "mappin.and.ellipse")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                VendorStatsBadges(
                    eventsCompleted: result.eventsCompletedCount,
                    ratingAvg: result.ratingAvg,
                    ratingCount: result.ratingCount
                )
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .proCard(padding: 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.Marketplace.vendorCard)
    }
}
