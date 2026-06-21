import Foundation

// MARK: - VendorProfileDTO
//
// Row in `vendor_profiles`. Decoding reads the full row (a `select *`); encoding
// is the OWNER WRITE payload — only the editable columns plus `profile_id` are
// sent, so the trigger-/E13-maintained stat columns and server timestamps are
// never clobbered by an upsert (mirrors `WaitlistEntryDTO`).
nonisolated struct VendorProfileDTO: Codable, Equatable {
    let profileID: UUID
    let category: String
    let serviceArea: String?
    let latitude: Double?
    let longitude: Double?
    let serviceRadiusKm: Double?
    let skills: [String]
    let searchName: String?
    let isListed: Bool
    // Server-managed (read-only on the client): never encoded.
    let eventsCompletedCount: Int
    let ratingAvg: Double?
    let ratingCount: Int
    let createdAt: PostgresTimestamp?
    let updatedAt: PostgresTimestamp?
    let deletedAt: PostgresTimestamp?

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case category
        case serviceArea = "service_area"
        case latitude
        case longitude
        case serviceRadiusKm = "service_radius_km"
        case skills
        case searchName = "search_name"
        case isListed = "is_listed"
        case eventsCompletedCount = "events_completed_count"
        case ratingAvg = "rating_avg"
        case ratingCount = "rating_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(
        profileID: UUID,
        category: String,
        serviceArea: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        serviceRadiusKm: Double? = nil,
        skills: [String] = [],
        searchName: String? = nil,
        isListed: Bool = false,
        eventsCompletedCount: Int = 0,
        ratingAvg: Double? = nil,
        ratingCount: Int = 0,
        createdAt: PostgresTimestamp? = nil,
        updatedAt: PostgresTimestamp? = nil,
        deletedAt: PostgresTimestamp? = nil
    ) {
        self.profileID = profileID
        self.category = category
        self.serviceArea = serviceArea
        self.latitude = latitude
        self.longitude = longitude
        self.serviceRadiusKm = serviceRadiusKm
        self.skills = skills
        self.searchName = searchName
        self.isListed = isListed
        self.eventsCompletedCount = eventsCompletedCount
        self.ratingAvg = ratingAvg
        self.ratingCount = ratingCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profileID, forKey: .profileID)
        try container.encode(category, forKey: .category)
        try container.encode(serviceArea, forKey: .serviceArea)              // nil → explicit NULL
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(serviceRadiusKm, forKey: .serviceRadiusKm)
        try container.encode(skills, forKey: .skills)
        try container.encode(searchName, forKey: .searchName)
        try container.encode(isListed, forKey: .isListed)
        // Stat columns + timestamps are server-managed — intentionally omitted.
    }
}

// MARK: - VendorSearchResultDTO
//
// One row from the `search_vendors` RPC (the `vendor_search_result` composite).
// Read-only — the display fields come from the public_profiles join, the rest
// from vendor_profiles, plus the computed `distance_km`.
nonisolated struct VendorSearchResultDTO: Decodable, Equatable, Identifiable {
    let profileID: UUID
    let displayName: String
    let businessName: String?
    let bio: String?
    let avatarURL: String?
    let category: String
    let skills: [String]
    let serviceArea: String?
    let latitude: Double?
    let longitude: Double?
    let serviceRadiusKm: Double?
    let eventsCompletedCount: Int
    let ratingAvg: Double?
    let ratingCount: Int
    let distanceKm: Double?

    var id: UUID { profileID }

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case displayName = "display_name"
        case businessName = "business_name"
        case bio
        case avatarURL = "avatar_url"
        case category
        case skills
        case serviceArea = "service_area"
        case latitude
        case longitude
        case serviceRadiusKm = "service_radius_km"
        case eventsCompletedCount = "events_completed_count"
        case ratingAvg = "rating_avg"
        case ratingCount = "rating_count"
        case distanceKm = "distance_km"
    }
}

// MARK: - PortfolioItemDTO
//
// Row in `portfolio_items`. Encoding is the create/update payload (timestamps are
// server-managed; soft-delete is a separate `deleted_at` update in the service).
nonisolated struct PortfolioItemDTO: Codable, Equatable, Identifiable {
    let id: UUID
    let profileID: UUID
    let kind: String
    let storagePath: String?
    let eventID: UUID?
    let caption: String?
    let sortOrder: Int
    let createdAt: PostgresTimestamp?
    let updatedAt: PostgresTimestamp?
    let deletedAt: PostgresTimestamp?

    enum CodingKeys: String, CodingKey {
        case id
        case profileID = "profile_id"
        case kind
        case storagePath = "storage_path"
        case eventID = "event_id"
        case caption
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(
        id: UUID = UUID(),
        profileID: UUID,
        kind: String,
        storagePath: String? = nil,
        eventID: UUID? = nil,
        caption: String? = nil,
        sortOrder: Int = 0,
        createdAt: PostgresTimestamp? = nil,
        updatedAt: PostgresTimestamp? = nil,
        deletedAt: PostgresTimestamp? = nil
    ) {
        self.id = id
        self.profileID = profileID
        self.kind = kind
        self.storagePath = storagePath
        self.eventID = eventID
        self.caption = caption
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(profileID, forKey: .profileID)
        try container.encode(kind, forKey: .kind)
        try container.encode(storagePath, forKey: .storagePath)
        try container.encode(eventID, forKey: .eventID)
        try container.encode(caption, forKey: .caption)
        try container.encode(sortOrder, forKey: .sortOrder)
        // Timestamps are server-managed — intentionally omitted.
    }
}

// MARK: - SavedVendorRowDTO
//
// Row in `saved_vendors` (E22). Insert posts both ids; the heart-state read
// selects only `vendor_profile_id`, so `plannerID` decodes as nil there.
nonisolated struct SavedVendorRowDTO: Codable, Equatable {
    let plannerID: UUID?
    let vendorProfileID: UUID

    init(plannerID: UUID? = nil, vendorProfileID: UUID) {
        self.plannerID = plannerID
        self.vendorProfileID = vendorProfileID
    }

    enum CodingKeys: String, CodingKey {
        case plannerID = "planner_id"
        case vendorProfileID = "vendor_profile_id"
    }
}

// MARK: - PublicProfileDTO
//
// Read projection of the `public_profiles` view (marketplace-safe identity).
nonisolated struct PublicProfileDTO: Decodable, Equatable {
    let id: UUID
    let displayName: String
    let businessName: String?
    let bio: String?
    let avatarURL: String?
    let portfolioURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case businessName = "business_name"
        case bio
        case avatarURL = "avatar_url"
        case portfolioURL = "portfolio_url"
    }
}

// MARK: - MarketplaceProfileIdentityDTO
//
// UPDATE payload for the reserved marketplace identity columns on `profiles`.
// Uses UPDATE (not upsert) because `authenticated` has no INSERT grant on
// profiles — the row already exists for any signed-in user. Synthesized
// Encodable omits nil fields (encodeIfPresent), so a partial update leaves unset
// columns untouched — notably the avatar isn't cleared when an edit doesn't
// change it.
nonisolated struct MarketplaceProfileIdentityDTO: Encodable, Equatable {
    let businessName: String?
    let bio: String?
    let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case businessName = "business_name"
        case bio
        case avatarURL = "avatar_url"
    }
}

// MARK: - PortfolioEventSummaryDTO
//
// One row from the `get_portfolio_event_summaries` RPC: the title + date of a
// verified shift_event portfolio item (events RLS is never widened).
nonisolated struct PortfolioEventSummaryDTO: Decodable, Equatable, Identifiable {
    let eventID: UUID
    let title: String
    let eventDate: PostgresTimestamp

    var id: UUID { eventID }

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case title
        case eventDate = "event_date"
    }
}
