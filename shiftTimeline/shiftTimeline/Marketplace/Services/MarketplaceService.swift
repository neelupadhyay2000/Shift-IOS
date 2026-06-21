import Foundation
import Models
import Supabase
import SwiftUI

// MARK: - Input / composite models

/// Editor input for the signed-in user's own vendor profile. `category` +
/// `customCategoryLabel` follow the waitlist convention (a custom type rides the
/// free-text category column).
struct VendorProfileInput: Sendable, Equatable {
    var businessName: String
    var bio: String
    var avatarURL: String?
    var category: VendorRole
    var customCategoryLabel: String
    var skills: [String]
    var serviceArea: String
    var latitude: Double?
    var longitude: Double?
    var serviceRadiusKm: Double?
    var isListed: Bool

    init(
        businessName: String = "",
        bio: String = "",
        avatarURL: String? = nil,
        category: VendorRole = .photographer,
        customCategoryLabel: String = "",
        skills: [String] = [],
        serviceArea: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        serviceRadiusKm: Double? = 80,
        isListed: Bool = false
    ) {
        self.businessName = businessName
        self.bio = bio
        self.avatarURL = avatarURL
        self.category = category
        self.customCategoryLabel = customCategoryLabel
        self.skills = skills
        self.serviceArea = serviceArea
        self.latitude = latitude
        self.longitude = longitude
        self.serviceRadiusKm = serviceRadiusKm
        self.isListed = isListed
    }
}

/// A vendor's public directory profile: the vendor_profiles row joined with the
/// public_profiles identity projection.
struct MarketplaceVendorProfile: Sendable, Equatable {
    let vendor: VendorProfileDTO
    let identity: PublicProfileDTO
}

/// Everything the profile editor needs to prefill: the existing vendor_profiles
/// row + identity (nil for a first-time opt-in), and the profile's default_role
/// as the initial category fallback.
struct VendorEditorPrefill: Sendable {
    let vendor: VendorProfileDTO?
    let identity: PublicProfileDTO?
    let defaultRole: VendorRole?
}

/// Minimal decode of `profiles.default_role` for the editor's category fallback.
nonisolated struct DefaultRoleRow: Decodable {
    let defaultRole: String?
    enum CodingKeys: String, CodingKey { case defaultRole = "default_role" }
}

/// Typed `search_vendors` RPC parameters. Kept as a struct so param construction
/// is pure and unit-testable, and the wire keys match the SQL arg names.
/// `nonisolated` so the synthesized `Encodable` conformance isn't inferred as
/// MainActor-isolated under the module's default isolation (matches the DTOs).
nonisolated struct SearchVendorsParams: Encodable, Equatable, Sendable {
    let pQuery: String?
    let pCategory: String?
    let pLat: Double?
    let pLng: Double?
    let pRadiusKm: Double?
    let pLimit: Int
    let pOffset: Int
    /// E18 availability filter: "yyyy-MM-dd" or nil for no date filter.
    let pOnDate: String?
    /// E22 sort: "rating" | "booked" | "nearest" or nil for the default order.
    let pSort: String?

    enum CodingKeys: String, CodingKey {
        case pQuery = "p_query"
        case pCategory = "p_category"
        case pLat = "p_lat"
        case pLng = "p_lng"
        case pRadiusKm = "p_radius_km"
        case pLimit = "p_limit"
        case pOffset = "p_offset"
        case pOnDate = "p_on_date"
        case pSort = "p_sort"
    }
}

/// Result ordering for the directory (maps to the search_vendors p_sort arg).
enum VendorSort: String, CaseIterable, Identifiable, Sendable {
    case rating
    case booked
    case nearest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rating:  String(localized: "Top rated")
        case .booked:  String(localized: "Most booked")
        case .nearest: String(localized: "Nearest")
        }
    }
}

// MARK: - Protocol

/// Read/write surface for the online-only vendor marketplace. Like the waitlist
/// and content-report services, this is NOT part of the SwiftData/Outbox sync
/// stack — every call is a direct, paginated SupabaseClient query / RPC.
protocol MarketplaceProviding: Sendable {
    /// Directory search via the `search_vendors` RPC (paginated).
    func searchVendors(
        query: String?,
        category: VendorRole?,
        latitude: Double?,
        longitude: Double?,
        radiusKm: Double?,
        limit: Int,
        offset: Int,
        onDate: Date?,
        sort: VendorSort?
    ) async throws -> [VendorSearchResultDTO]

    /// A listed vendor's public profile (vendor_profiles ⋈ public_profiles), or
    /// nil if there is no visible profile for that id.
    func fetchVendorProfile(profileID: UUID) async throws -> MarketplaceVendorProfile?

    /// The caller's saved (favourited) vendors as directory cards (newest first).
    func savedVendors() async throws -> [VendorSearchResultDTO]

    /// The ids the caller has saved — for rendering the heart state on cards.
    func savedVendorIDs() async throws -> Set<UUID>

    /// Save / unsave a vendor to the caller's shortlist.
    func saveVendor(profileID: UUID) async throws
    func unsaveVendor(profileID: UUID) async throws

    /// The signed-in user's own vendor_profiles row (listed or not), or nil.
    func fetchMyVendorProfile() async throws -> VendorProfileDTO?

    /// Flips just the marketplace listing visibility on the caller's vendor row
    /// (the Settings "Show me in the marketplace" toggle).
    func setListed(_ listed: Bool) async throws

    /// Prefill bundle for the editor: existing vendor row + identity + default role.
    func fetchMyProfilePrefill() async throws -> VendorEditorPrefill

    /// Completed events the caller may still add to their portfolio (RPC).
    func claimablePortfolioEvents() async throws -> [PortfolioEventSummaryDTO]

    /// Persists a new display order by writing each item's `sort_order` to its
    /// index in `orderedIDs`.
    func reorderPortfolio(orderedIDs: [UUID]) async throws

    /// Upserts the caller's vendor profile: writes the reserved identity columns
    /// on `profiles` and the marketplace columns on `vendor_profiles`, keeping
    /// `search_name` in sync with the business name.
    @discardableResult
    func upsertMyVendorProfile(_ input: VendorProfileInput) async throws -> VendorProfileDTO

    /// A vendor's live portfolio items, ordered by `sort_order`.
    func portfolioItems(profileID: UUID) async throws -> [PortfolioItemDTO]

    /// Verified shift_event summaries (title + date) via RPC — events RLS unwidened.
    func portfolioEventSummaries(profileID: UUID) async throws -> [PortfolioEventSummaryDTO]

    @discardableResult
    func addPortfolioItem(_ item: PortfolioItemDTO) async throws -> PortfolioItemDTO

    @discardableResult
    func updatePortfolioItem(_ item: PortfolioItemDTO) async throws -> PortfolioItemDTO

    /// Soft-deletes a portfolio item (sets `deleted_at`).
    func deletePortfolioItem(id: UUID) async throws

    /// Uploads a portfolio image to `vendor-portfolio/{uid}/{uuid}.{ext}` and
    /// returns the stored object path (persisted on the portfolio item).
    func uploadPortfolioImage(data: Data, fileExtension: String) async throws -> String

    /// Uploads the avatar to `vendor-portfolio/{uid}/avatar.jpg` (overwriting) and
    /// returns its public URL (written to `profiles.avatar_url` via the editor).
    func uploadAvatar(data: Data) async throws -> URL

    /// Public CDN URL for a portfolio object path (the bucket is public).
    func portfolioImageURL(forPath path: String) -> URL?

    /// The signed-in user's profile id (used to scope "my" portfolio writes).
    func currentProfileID() async throws -> UUID
}

// MARK: - Supabase implementation

/// Supabase-backed ``MarketplaceProviding``. Stateless — holds only the shared
/// client; RLS scopes self-writes and the `*_public_select` policies / RPCs gate
/// directory reads.
struct SupabaseMarketplaceService: MarketplaceProviding {
    private let client: SupabaseClient
    private let bucket = "vendor-portfolio"

    init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: Search

    func searchVendors(
        query: String?,
        category: VendorRole?,
        latitude: Double?,
        longitude: Double?,
        radiusKm: Double?,
        limit: Int = 20,
        offset: Int = 0,
        onDate: Date? = nil,
        sort: VendorSort? = nil
    ) async throws -> [VendorSearchResultDTO] {
        let params = Self.searchParams(
            query: query,
            category: category,
            latitude: latitude,
            longitude: longitude,
            radiusKm: radiusKm,
            limit: limit,
            offset: offset,
            onDate: onDate,
            sort: sort
        )
        return try await client
            .rpc("search_vendors", params: params)
            .execute()
            .value
    }

    // MARK: Profile fetch

    func fetchVendorProfile(profileID: UUID) async throws -> MarketplaceVendorProfile? {
        let vendors: [VendorProfileDTO] = try await client
            .from("vendor_profiles")
            .select()
            .eq("profile_id", value: profileID.uuidString)
            .execute()
            .value
        guard let vendor = vendors.first(where: { $0.deletedAt == nil }) else { return nil }

        let identities: [PublicProfileDTO] = try await client
            .from("public_profiles")
            .select()
            .eq("id", value: profileID.uuidString)
            .execute()
            .value
        guard let identity = identities.first else { return nil }

        return MarketplaceVendorProfile(vendor: vendor, identity: identity)
    }

    func savedVendors() async throws -> [VendorSearchResultDTO] {
        try await client.rpc("get_saved_vendors").execute().value
    }

    func savedVendorIDs() async throws -> Set<UUID> {
        let uid = try await client.auth.session.user.id
        let rows: [SavedVendorRowDTO] = try await client
            .from("saved_vendors")
            .select("vendor_profile_id")
            .eq("planner_id", value: uid.uuidString)
            .execute()
            .value
        return Set(rows.map(\.vendorProfileID))
    }

    func saveVendor(profileID: UUID) async throws {
        let uid = try await client.auth.session.user.id
        try await client
            .from("saved_vendors")
            .upsert(SavedVendorRowDTO(plannerID: uid, vendorProfileID: profileID), onConflict: "planner_id,vendor_profile_id")
            .execute()
    }

    func unsaveVendor(profileID: UUID) async throws {
        let uid = try await client.auth.session.user.id
        try await client
            .from("saved_vendors")
            .delete()
            .eq("planner_id", value: uid.uuidString)
            .eq("vendor_profile_id", value: profileID.uuidString)
            .execute()
    }

    func fetchMyVendorProfile() async throws -> VendorProfileDTO? {
        let uid = try await client.auth.session.user.id
        let rows: [VendorProfileDTO] = try await client
            .from("vendor_profiles")
            .select()
            .eq("profile_id", value: uid.uuidString)
            .execute()
            .value
        return rows.first { $0.deletedAt == nil }
    }

    func setListed(_ listed: Bool) async throws {
        let uid = try await client.auth.session.user.id
        try await client
            .from("vendor_profiles")
            .update(["is_listed": listed])
            .eq("profile_id", value: uid.uuidString)
            .execute()
    }

    func fetchMyProfilePrefill() async throws -> VendorEditorPrefill {
        let uid = try await client.auth.session.user.id

        let vendors: [VendorProfileDTO] = try await client
            .from("vendor_profiles").select().eq("profile_id", value: uid.uuidString)
            .execute().value
        let identities: [PublicProfileDTO] = try await client
            .from("public_profiles").select().eq("id", value: uid.uuidString)
            .execute().value
        let roleRows: [DefaultRoleRow] = try await client
            .from("profiles").select("default_role").eq("id", value: uid.uuidString)
            .execute().value

        let defaultRole = roleRows.first?.defaultRole.flatMap { VendorRole(rawValue: $0) }
        return VendorEditorPrefill(
            vendor: vendors.first { $0.deletedAt == nil },
            identity: identities.first,
            defaultRole: defaultRole
        )
    }

    func claimablePortfolioEvents() async throws -> [PortfolioEventSummaryDTO] {
        try await client
            .rpc("get_claimable_portfolio_events")
            .execute()
            .value
    }

    func reorderPortfolio(orderedIDs: [UUID]) async throws {
        for (index, id) in orderedIDs.enumerated() {
            try await client
                .from("portfolio_items")
                .update(["sort_order": index])
                .eq("id", value: id.uuidString)
                .execute()
        }
    }

    // MARK: Profile upsert

    @discardableResult
    func upsertMyVendorProfile(_ input: VendorProfileInput) async throws -> VendorProfileDTO {
        let uid = try await client.auth.session.user.id

        // 1) Identity → profiles reserved columns (UPDATE: no INSERT grant, and the
        //    row already exists for any signed-in user).
        let identity = Self.identityPayload(input)
        try await client
            .from("profiles")
            .update(identity)
            .eq("id", value: uid.uuidString)
            .execute()

        // 2) Marketplace columns → vendor_profiles (upsert on profile_id), with
        //    search_name kept in sync with the business name.
        let payload = Self.vendorProfilePayload(profileID: uid, input: input)
        return try await client
            .from("vendor_profiles")
            .upsert(payload, onConflict: "profile_id")
            .select()
            .single()
            .execute()
            .value
    }

    // MARK: Portfolio

    func portfolioItems(profileID: UUID) async throws -> [PortfolioItemDTO] {
        try await client
            .from("portfolio_items")
            .select()
            .eq("profile_id", value: profileID.uuidString)
            .is("deleted_at", value: nil)
            .order("sort_order", ascending: true)
            .execute()
            .value
    }

    func portfolioEventSummaries(profileID: UUID) async throws -> [PortfolioEventSummaryDTO] {
        try await client
            .rpc("get_portfolio_event_summaries", params: ["p_profile_id": profileID.uuidString])
            .execute()
            .value
    }

    @discardableResult
    func addPortfolioItem(_ item: PortfolioItemDTO) async throws -> PortfolioItemDTO {
        try await client
            .from("portfolio_items")
            .insert(item)
            .select()
            .single()
            .execute()
            .value
    }

    @discardableResult
    func updatePortfolioItem(_ item: PortfolioItemDTO) async throws -> PortfolioItemDTO {
        try await client
            .from("portfolio_items")
            .update(item)
            .eq("id", value: item.id.uuidString)
            .select()
            .single()
            .execute()
            .value
    }

    func deletePortfolioItem(id: UUID) async throws {
        try await client
            .from("portfolio_items")
            .update(["deleted_at": SupabaseTimestamp.string(from: Date())])
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: Storage

    func uploadPortfolioImage(data: Data, fileExtension: String) async throws -> String {
        let uid = try await client.auth.session.user.id
        let ext = Self.normalizedExtension(fileExtension)
        // Lowercased uid: the storage RLS owner check compares the first path
        // segment to auth.uid()::text (lowercase). Swift's UUID.uuidString is
        // uppercase, so without this every upload is denied by RLS.
        let path = "\(uid.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\(ext)"
        _ = try await client.storage
            .from(bucket)
            .upload(path, data: data, options: FileOptions(contentType: Self.mimeType(for: ext)))
        return path
    }

    func uploadAvatar(data: Data) async throws -> URL {
        let uid = try await client.auth.session.user.id
        // Lowercased uid — see uploadPortfolioImage (storage RLS owner check).
        let path = "\(uid.uuidString.lowercased())/avatar.jpg"
        _ = try await client.storage
            .from(bucket)
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
        return try client.storage.from(bucket).getPublicURL(path: path)
    }

    func portfolioImageURL(forPath path: String) -> URL? {
        try? client.storage.from(bucket).getPublicURL(path: path)
    }

    func currentProfileID() async throws -> UUID {
        try await client.auth.session.user.id
    }

    // MARK: - Pure builders (unit-tested)

    /// Builds the `search_vendors` params: empty query/category collapse to nil
    /// (the RPC treats null as "no filter"); the category enum maps to its raw
    /// value; limit/offset pass through (the RPC clamps the limit server-side).
    static func searchParams(
        query: String?,
        category: VendorRole?,
        latitude: Double?,
        longitude: Double?,
        radiusKm: Double?,
        limit: Int,
        offset: Int,
        onDate: Date? = nil,
        sort: VendorSort? = nil
    ) -> SearchVendorsParams {
        let trimmedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        return SearchVendorsParams(
            pQuery: (trimmedQuery?.isEmpty == false) ? trimmedQuery : nil,
            pCategory: category?.rawValue,
            pLat: latitude,
            pLng: longitude,
            pRadiusKm: radiusKm,
            pLimit: limit,
            pOffset: max(0, offset),
            pOnDate: onDate.map { CalendarDay.string(from: $0) },
            pSort: sort?.rawValue
        )
    }

    /// Lowercased, trimmed denormalisation of the business name (nil when empty).
    static func searchName(forBusinessName businessName: String) -> String? {
        let normalized = businessName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    /// Resolves the stored category: a non-empty custom label rides the free-text
    /// column in place of the `custom` raw value (mirrors event_vendors.role).
    static func resolvedCategory(_ category: VendorRole, customLabel: String) -> String {
        let trimmed = customLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if category == .custom, !trimmed.isEmpty { return trimmed }
        return category.rawValue
    }

    /// vendor_profiles write payload from editor input.
    static func vendorProfilePayload(profileID: UUID, input: VendorProfileInput) -> VendorProfileDTO {
        VendorProfileDTO(
            profileID: profileID,
            category: resolvedCategory(input.category, customLabel: input.customCategoryLabel),
            serviceArea: input.serviceArea.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            latitude: input.latitude,
            longitude: input.longitude,
            serviceRadiusKm: input.serviceRadiusKm,
            // Skills normalised to lowercase tokens so the && overlap search matches.
            skills: input.skills
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty },
            searchName: searchName(forBusinessName: input.businessName),
            isListed: input.isListed
        )
    }

    /// profiles identity write payload (reserved marketplace columns).
    static func identityPayload(_ input: VendorProfileInput) -> MarketplaceProfileIdentityDTO {
        MarketplaceProfileIdentityDTO(
            businessName: input.businessName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            bio: input.bio.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            avatarURL: input.avatarURL
        )
    }

    static func normalizedExtension(_ ext: String) -> String {
        let lower = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return lower == "jpeg" ? "jpg" : lower
    }

    static func mimeType(for ext: String) -> String {
        switch normalizedExtension(ext) {
        case "png":  "image/png"
        case "heic": "image/heic"
        case "webp": "image/webp"
        case "mp4":  "video/mp4"
        case "mov":  "video/quicktime"
        default:     "image/jpeg"
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Environment

private struct MarketplaceServiceKey: EnvironmentKey {
    static let defaultValue: (any MarketplaceProviding)? = nil
}

extension EnvironmentValues {
    var marketplaceService: (any MarketplaceProviding)? {
        get { self[MarketplaceServiceKey.self] }
        set { self[MarketplaceServiceKey.self] = newValue }
    }
}
