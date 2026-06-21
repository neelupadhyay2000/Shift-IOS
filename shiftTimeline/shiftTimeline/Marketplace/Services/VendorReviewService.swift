import Foundation
import Supabase
import SwiftUI

// MARK: - Params

/// Typed args for the `get_vendor_reviews` RPC (wire keys match the SQL).
nonisolated struct GetVendorReviewsParams: Encodable, Equatable, Sendable {
    let pVendorProfileID: UUID
    let pLimit: Int
    let pOffset: Int

    enum CodingKeys: String, CodingKey {
        case pVendorProfileID = "p_vendor_profile_id"
        case pLimit = "p_limit"
        case pOffset = "p_offset"
    }
}

// MARK: - Protocol

/// Verified reviews + verified stats (E17). Online-only direct Supabase access,
/// like the other marketplace services. Writes go through the gated
/// `submit_vendor_review` RPC (insert) and the reviewer's own UPDATE policy
/// (edit / soft-delete); reads come from `get_vendor_reviews` + `vendor_public_stats`.
protocol VendorReviewing: Sendable {
    /// Paginated reviews for a listed vendor (newest first), with reviewer name +
    /// event title/date resolved server-side.
    func reviews(vendorProfileID: UUID, limit: Int, offset: Int) async throws -> [VendorReviewDTO]

    /// Profile-detail "Verified by Shift" stats for one vendor, or nil if unlisted.
    func stats(profileID: UUID) async throws -> VendorPublicStatsDTO?

    /// The caller's own review of a vendor on an event, if one exists (incl. a
    /// soft-deleted one — editing resurrects it). Used to prefill the composer.
    func myReview(eventID: UUID, vendorProfileID: UUID) async throws -> VendorReviewRowDTO?

    /// Submit a new review via the gated RPC. Throws if the gates fail or a review
    /// already exists (unique constraint) — callers route an existing review to `update`.
    @discardableResult
    func submitReview(eventID: UUID, vendorProfileID: UUID, rating: Int, body: String) async throws -> VendorReviewRowDTO

    /// Edit the caller's own review (also un-deletes a previously removed one).
    @discardableResult
    func updateReview(reviewID: UUID, rating: Int, body: String) async throws -> VendorReviewRowDTO

    /// Soft-delete the caller's own review (sets `deleted_at`).
    func deleteReview(reviewID: UUID) async throws
}

// MARK: - Supabase implementation

@MainActor
struct SupabaseVendorReviewService: VendorReviewing {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func reviews(vendorProfileID: UUID, limit: Int = 20, offset: Int = 0) async throws -> [VendorReviewDTO] {
        let params = GetVendorReviewsParams(
            pVendorProfileID: vendorProfileID,
            pLimit: limit,
            pOffset: max(0, offset)
        )
        return try await client
            .rpc("get_vendor_reviews", params: params)
            .execute()
            .value
    }

    func stats(profileID: UUID) async throws -> VendorPublicStatsDTO? {
        let rows: [VendorPublicStatsDTO] = try await client
            .from("vendor_public_stats")
            .select()
            .eq("profile_id", value: profileID.uuidString)
            .execute()
            .value
        return rows.first
    }

    func myReview(eventID: UUID, vendorProfileID: UUID) async throws -> VendorReviewRowDTO? {
        let uid = try await client.auth.session.user.id
        let rows: [VendorReviewRowDTO] = try await client
            .from("vendor_reviews")
            .select()
            .eq("event_id", value: eventID.uuidString)
            .eq("vendor_profile_id", value: vendorProfileID.uuidString)
            .eq("reviewer_id", value: uid.uuidString)
            .execute()
            .value
        return rows.first
    }

    @discardableResult
    func submitReview(eventID: UUID, vendorProfileID: UUID, rating: Int, body: String) async throws -> VendorReviewRowDTO {
        let params = SubmitReviewParams(
            pEventID: eventID,
            pVendorProfileID: vendorProfileID,
            pRating: Self.clampRating(rating),
            pBody: body.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let rows: [VendorReviewRowDTO] = try await client
            .rpc("submit_vendor_review", params: params)
            .execute()
            .value
        guard let row = rows.first else { throw VendorReviewError.emptyResponse }
        return row
    }

    @discardableResult
    func updateReview(reviewID: UUID, rating: Int, body: String) async throws -> VendorReviewRowDTO {
        let payload = VendorReviewUpdateDTO(
            rating: Self.clampRating(rating),
            body: body.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        return try await client
            .from("vendor_reviews")
            .update(payload)
            .eq("id", value: reviewID.uuidString)
            .select()
            .single()
            .execute()
            .value
    }

    func deleteReview(reviewID: UUID) async throws {
        try await client
            .from("vendor_reviews")
            .update(["deleted_at": SupabaseTimestamp.string(from: Date())])
            .eq("id", value: reviewID.uuidString)
            .execute()
    }

    // MARK: - Pure helpers (unit-tested)

    /// Clamps a star rating into the table's 1...5 CHECK range.
    nonisolated static func clampRating(_ rating: Int) -> Int {
        min(5, max(1, rating))
    }
}

enum VendorReviewError: Error {
    case emptyResponse
}

// MARK: - Environment

private struct VendorReviewServiceKey: EnvironmentKey {
    static let defaultValue: (any VendorReviewing)? = nil
}

extension EnvironmentValues {
    var vendorReviewService: (any VendorReviewing)? {
        get { self[VendorReviewServiceKey.self] }
        set { self[VendorReviewServiceKey.self] = newValue }
    }
}
