import Foundation

// MARK: - VendorReviewDTO
//
// One row from the `get_vendor_reviews` RPC: the review plus the reviewer's
// display name and the worked event's title/date (joined past RLS server-side).
// Read-only — reviews are written via `submit_vendor_review` / the edit path.
nonisolated struct VendorReviewDTO: Decodable, Equatable, Identifiable {
    let id: UUID
    let eventID: UUID
    let reviewerID: UUID
    let rating: Int
    let body: String
    let createdAt: PostgresTimestamp
    let reviewerName: String
    let eventTitle: String?
    let eventDate: PostgresTimestamp?

    enum CodingKeys: String, CodingKey {
        case id
        case eventID = "event_id"
        case reviewerID = "reviewer_id"
        case rating
        case body
        case createdAt = "created_at"
        case reviewerName = "reviewer_name"
        case eventTitle = "event_title"
        case eventDate = "event_date"
    }
}

// MARK: - VendorReviewRowDTO
//
// The raw `vendor_reviews` row — what `submit_vendor_review` returns and what the
// composer reads to prefill an existing review for editing (reviewer self-select).
nonisolated struct VendorReviewRowDTO: Decodable, Equatable, Identifiable {
    let id: UUID
    let eventID: UUID
    let vendorProfileID: UUID
    let reviewerID: UUID
    let rating: Int
    let body: String
    let createdAt: PostgresTimestamp?
    let deletedAt: PostgresTimestamp?

    enum CodingKeys: String, CodingKey {
        case id
        case eventID = "event_id"
        case vendorProfileID = "vendor_profile_id"
        case reviewerID = "reviewer_id"
        case rating
        case body
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }
}

// MARK: - SubmitReviewParams
//
// Typed args for the `submit_vendor_review` RPC; wire keys match the SQL arg
// names. `nonisolated` so the synthesized Encodable isn't MainActor-isolated.
nonisolated struct SubmitReviewParams: Encodable, Equatable, Sendable {
    let pEventID: UUID
    let pVendorProfileID: UUID
    let pRating: Int
    let pBody: String

    enum CodingKeys: String, CodingKey {
        case pEventID = "p_event_id"
        case pVendorProfileID = "p_vendor_profile_id"
        case pRating = "p_rating"
        case pBody = "p_body"
    }
}

// MARK: - VendorReviewUpdateDTO
//
// Edit payload for the reviewer's own review (the reviewer UPDATE policy allows
// changing only rating/body/deleted_at — event/vendor/reviewer are frozen by the
// guard). Always writes deleted_at = null so editing also resurrects a review the
// reviewer had previously soft-deleted (one slot per event/vendor; the unique
// constraint blocks a fresh insert, so re-reviewing means un-deleting + editing).
nonisolated struct VendorReviewUpdateDTO: Encodable, Equatable {
    let rating: Int
    let body: String

    enum CodingKeys: String, CodingKey {
        case rating
        case body
        case deletedAt = "deleted_at"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rating, forKey: .rating)
        try container.encode(body, forKey: .body)
        try container.encodeNil(forKey: .deletedAt)   // clear any tombstone
    }
}

// MARK: - VendorPublicStatsDTO
//
// One row from the `vendor_public_stats` view (queried filtered to one profile).
nonisolated struct VendorPublicStatsDTO: Decodable, Equatable {
    let profileID: UUID
    let eventsCompleted: Int
    let repeatPlannerCount: Int
    let reliabilityPct: Int?

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case eventsCompleted = "events_completed"
        case repeatPlannerCount = "repeat_planner_count"
        case reliabilityPct = "reliability_pct"
    }
}
