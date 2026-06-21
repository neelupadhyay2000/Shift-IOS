import Foundation
@testable import shiftTimeline
import Testing

@Suite("VendorReviewService — params, payloads, decoding")
struct VendorReviewServiceTests {

    // MARK: clampRating

    @Test("clampRating constrains to 1...5")
    func clampRating() {
        #expect(SupabaseVendorReviewService.clampRating(0) == 1)
        #expect(SupabaseVendorReviewService.clampRating(-3) == 1)
        #expect(SupabaseVendorReviewService.clampRating(3) == 3)
        #expect(SupabaseVendorReviewService.clampRating(5) == 5)
        #expect(SupabaseVendorReviewService.clampRating(9) == 5)
    }

    // MARK: submit_vendor_review params

    @Test("submit params encode the p_ wire keys")
    func submitParamsEncoding() throws {
        let event = UUID(); let vendor = UUID()
        let params = SubmitReviewParams(pEventID: event, pVendorProfileID: vendor, pRating: 4, pBody: "great")
        let json = try jsonObject(from: params)
        #expect(json["p_event_id"] as? String == event.uuidString)
        #expect(json["p_vendor_profile_id"] as? String == vendor.uuidString)
        #expect(json["p_rating"] as? Int == 4)
        #expect(json["p_body"] as? String == "great")
    }

    @Test("get_vendor_reviews params encode the p_ wire keys")
    func getReviewsParamsEncoding() throws {
        let vendor = UUID()
        let params = GetVendorReviewsParams(pVendorProfileID: vendor, pLimit: 20, pOffset: 40)
        let json = try jsonObject(from: params)
        #expect(json["p_vendor_profile_id"] as? String == vendor.uuidString)
        #expect(json["p_limit"] as? Int == 20)
        #expect(json["p_offset"] as? Int == 40)
    }

    // MARK: update payload (always clears deleted_at)

    @Test("update payload encodes rating/body and an explicit null deleted_at")
    func updatePayloadEncoding() throws {
        let payload = VendorReviewUpdateDTO(rating: 5, body: "updated")
        let json = try jsonObject(from: payload)
        #expect(json["rating"] as? Int == 5)
        #expect(json["body"] as? String == "updated")
        // Explicit NULL un-deletes a previously soft-deleted review on edit.
        #expect(json.keys.contains("deleted_at"))
        #expect(json["deleted_at"] is NSNull)
    }

    // MARK: decoding

    @Test("VendorReviewDTO decodes the RPC row incl. nullable event fields")
    func reviewDTODecoding() throws {
        let id = UUID(); let event = UUID(); let reviewer = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "event_id": "\(event.uuidString)",
          "reviewer_id": "\(reviewer.uuidString)",
          "rating": 5,
          "body": "Fantastic work",
          "created_at": "2026-06-21T00:00:00Z",
          "reviewer_name": "Sarah",
          "event_title": "Sarah's Wedding",
          "event_date": "2026-05-01T00:00:00Z"
        }
        """
        let dto = try decodeDTO(VendorReviewDTO.self, from: json)
        #expect(dto.id == id)
        #expect(dto.eventID == event)
        #expect(dto.reviewerID == reviewer)
        #expect(dto.rating == 5)
        #expect(dto.reviewerName == "Sarah")
        #expect(dto.eventTitle == "Sarah's Wedding")
        #expect(dto.eventDate != nil)
    }

    @Test("VendorReviewDTO tolerates null event_title/date")
    func reviewDTODecodingNullEvent() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "event_id": "\(UUID().uuidString)",
          "reviewer_id": "\(UUID().uuidString)",
          "rating": 3,
          "body": "",
          "created_at": "2026-06-21T00:00:00Z",
          "reviewer_name": "Planner",
          "event_title": null,
          "event_date": null
        }
        """
        let dto = try decodeDTO(VendorReviewDTO.self, from: json)
        #expect(dto.eventTitle == nil)
        #expect(dto.eventDate == nil)
        #expect(dto.body.isEmpty)
    }

    @Test("VendorPublicStatsDTO decodes the view row incl. null reliability")
    func statsDTODecoding() throws {
        let profile = UUID()
        let json = """
        { "profile_id": "\(profile.uuidString)", "events_completed": 7, "repeat_planner_count": 2, "reliability_pct": 83 }
        """
        let dto = try decodeDTO(VendorPublicStatsDTO.self, from: json)
        #expect(dto.profileID == profile)
        #expect(dto.eventsCompleted == 7)
        #expect(dto.repeatPlannerCount == 2)
        #expect(dto.reliabilityPct == 83)

        let nullRel = """
        { "profile_id": "\(profile.uuidString)", "events_completed": 0, "repeat_planner_count": 0, "reliability_pct": null }
        """
        let dto2 = try decodeDTO(VendorPublicStatsDTO.self, from: nullRel)
        #expect(dto2.reliabilityPct == nil)
    }

    @Test("VendorReviewRowDTO decodes the submit_vendor_review return row")
    func reviewRowDecoding() throws {
        let id = UUID(); let event = UUID(); let vendor = UUID(); let reviewer = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "event_id": "\(event.uuidString)",
          "vendor_profile_id": "\(vendor.uuidString)",
          "reviewer_id": "\(reviewer.uuidString)",
          "rating": 4,
          "body": "Solid",
          "created_at": "2026-06-21T00:00:00Z",
          "updated_at": "2026-06-21T00:00:00Z",
          "deleted_at": null
        }
        """
        let dto = try decodeDTO(VendorReviewRowDTO.self, from: json)
        #expect(dto.id == id)
        #expect(dto.vendorProfileID == vendor)
        #expect(dto.rating == 4)
        #expect(dto.deletedAt == nil)
    }
}
