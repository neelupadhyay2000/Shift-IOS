import Foundation

// MARK: - Interest Role

/// Which side of the marketplace the user is signing up for. Raw values match
/// the `marketplace_waitlist.interest_role` CHECK constraint exactly
/// (`vendor` | `planner` | `both`). Display strings live with the UI
/// (`WaitlistSignupSheet`), mirroring the `VendorRole` convention.
enum WaitlistInterestRole: String, CaseIterable {
    case vendor
    case planner
    case both
}

// MARK: - DTO

/// Row in the Supabase `marketplace_waitlist` table (one per profile,
/// `profile_id` unique). `interest_role` and `category` are coded as plain
/// text; the typed `WaitlistInterestRole` / `VendorRole` conversion happens
/// in `SupabaseWaitlistService` payload construction and in the signup sheet.
///
/// Encoding is the **write payload**, with two deliberate deviations from the
/// synthesized form:
/// - `category` and `deleted_at` are encoded as explicit NULL when nil, so a
///   planner upsert clears a stale vendor category and re-joining resurrects
///   a soft-deleted row (PostgREST ignores omitted columns on upsert).
/// - `created_at` / `updated_at` are server-managed and never sent.
nonisolated struct WaitlistEntryDTO: Codable, Equatable {
    let profileID: UUID
    let interestRole: String
    let category: String?
    let region: String
    let createdAt: PostgresTimestamp?
    let updatedAt: PostgresTimestamp?
    let deletedAt: PostgresTimestamp?

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case interestRole = "interest_role"
        case category
        case region
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(
        profileID: UUID,
        interestRole: String,
        category: String? = nil,
        region: String,
        createdAt: PostgresTimestamp? = nil,
        updatedAt: PostgresTimestamp? = nil,
        deletedAt: PostgresTimestamp? = nil
    ) {
        self.profileID = profileID
        self.interestRole = interestRole
        self.category = category
        self.region = region
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profileID, forKey: .profileID)
        try container.encode(interestRole, forKey: .interestRole)
        try container.encode(category, forKey: .category)   // nil → explicit NULL
        try container.encode(region, forKey: .region)
        try container.encodeNil(forKey: .deletedAt)          // always resurrect
    }
}
