import Foundation
@testable import shiftTimeline
import Testing

@Suite("Marketplace DTOs — coding")
struct MarketplaceDTOTests {

    // MARK: VendorProfileDTO

    @Test("vendor profile decodes a full PostgREST row")
    func vendorProfileDecodes() throws {
        let pid = UUID()
        let json = """
        {
            "profile_id": "\(pid.uuidString)",
            "category": "photographer",
            "service_area": "Toronto, ON",
            "latitude": 43.65,
            "longitude": -79.38,
            "service_radius_km": 80,
            "skills": ["wedding", "portrait"],
            "search_name": "golden hour studios",
            "is_listed": true,
            "events_completed_count": 12,
            "rating_avg": 4.9,
            "rating_count": 8,
            "created_at": "2026-06-04T16:00:00Z",
            "updated_at": "2026-06-04T16:00:00Z",
            "deleted_at": null
        }
        """
        let dto = try decodeDTO(VendorProfileDTO.self, from: json)
        #expect(dto.profileID == pid)
        #expect(dto.category == "photographer")
        #expect(dto.skills == ["wedding", "portrait"])
        #expect(dto.isListed)
        #expect(dto.eventsCompletedCount == 12)
        #expect(dto.ratingAvg == 4.9)
        #expect(dto.deletedAt == nil)
    }

    @Test("vendor profile encode is the editable write payload only")
    func vendorProfileEncodeOmitsServerManaged() throws {
        let dto = VendorProfileDTO(
            profileID: UUID(),
            category: "dj",
            serviceArea: "Ottawa, ON",
            latitude: nil,
            longitude: nil,
            serviceRadiusKm: 50,
            skills: ["club"],
            searchName: "atlas sound",
            isListed: false,
            eventsCompletedCount: 99,   // server-managed — must NOT be sent
            ratingAvg: 5.0,
            ratingCount: 3
        )
        let json = try jsonObject(from: dto)
        #expect(json["profile_id"] != nil)
        #expect(json["category"] as? String == "dj")
        #expect(json["search_name"] as? String == "atlas sound")
        #expect(json["is_listed"] as? Bool == false)
        #expect(json["skills"] as? [String] == ["club"])
        #expect(json["latitude"] is NSNull)        // nil → explicit NULL
        // Server-managed columns are never written.
        #expect(json["events_completed_count"] == nil)
        #expect(json["rating_avg"] == nil)
        #expect(json["created_at"] == nil)
        #expect(json["updated_at"] == nil)
    }

    // MARK: VendorSearchResultDTO

    @Test("search result decodes the RPC composite row")
    func searchResultDecodes() throws {
        let pid = UUID()
        let json = """
        {
            "profile_id": "\(pid.uuidString)",
            "display_name": "",
            "business_name": "Stem & Petal",
            "bio": "Floral design",
            "avatar_url": null,
            "category": "florist",
            "skills": ["floral"],
            "service_area": "Toronto, ON",
            "latitude": 43.66,
            "longitude": -79.39,
            "service_radius_km": 80,
            "events_completed_count": 3,
            "rating_avg": 5.0,
            "rating_count": 4,
            "distance_km": 0.7
        }
        """
        let dto = try decodeDTO(VendorSearchResultDTO.self, from: json)
        #expect(dto.id == pid)
        #expect(dto.businessName == "Stem & Petal")
        #expect(dto.category == "florist")
        #expect(dto.distanceKm == 0.7)
        #expect(dto.avatarURL == nil)
    }

    @Test("search result tolerates a null distance (no point supplied)")
    func searchResultNullDistance() throws {
        let json = """
        {
            "profile_id": "\(UUID().uuidString)",
            "display_name": "Vendor",
            "business_name": null, "bio": null, "avatar_url": null,
            "category": "custom", "skills": [], "service_area": null,
            "latitude": null, "longitude": null, "service_radius_km": null,
            "events_completed_count": 0, "rating_avg": null, "rating_count": 0,
            "distance_km": null
        }
        """
        let dto = try decodeDTO(VendorSearchResultDTO.self, from: json)
        #expect(dto.distanceKm == nil)
        #expect(dto.ratingAvg == nil)
        #expect(dto.skills.isEmpty)
    }

    // MARK: PortfolioItemDTO

    @Test("portfolio item decodes a shift_event row")
    func portfolioItemDecodes() throws {
        let id = UUID(); let pid = UUID(); let eid = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "profile_id": "\(pid.uuidString)",
            "kind": "shift_event",
            "storage_path": null,
            "event_id": "\(eid.uuidString)",
            "caption": "Sarah's wedding",
            "sort_order": 2,
            "created_at": "2026-06-04T16:00:00Z",
            "updated_at": "2026-06-04T16:00:00Z",
            "deleted_at": null
        }
        """
        let dto = try decodeDTO(PortfolioItemDTO.self, from: json)
        #expect(dto.id == id)
        #expect(dto.kind == "shift_event")
        #expect(dto.eventID == eid)
        #expect(dto.sortOrder == 2)
    }

    @Test("portfolio item encode omits server timestamps")
    func portfolioItemEncodeOmitsTimestamps() throws {
        let dto = PortfolioItemDTO(
            profileID: UUID(),
            kind: "photo",
            storagePath: "uid/abc.jpg",
            caption: "Cover",
            sortOrder: 0,
            createdAt: fixedPGTimestamp,
            updatedAt: fixedPGTimestamp
        )
        let json = try jsonObject(from: dto)
        #expect(json["id"] != nil)
        #expect(json["kind"] as? String == "photo")
        #expect(json["storage_path"] as? String == "uid/abc.jpg")
        #expect(json["event_id"] is NSNull)
        #expect(json["created_at"] == nil)
        #expect(json["updated_at"] == nil)
    }

    // MARK: PortfolioEventSummaryDTO

    @Test("event summary decodes the RPC row")
    func eventSummaryDecodes() throws {
        let eid = UUID()
        let json = """
        { "event_id": "\(eid.uuidString)", "title": "Gala", "event_date": "2026-06-04T16:00:00Z" }
        """
        let dto = try decodeDTO(PortfolioEventSummaryDTO.self, from: json)
        #expect(dto.id == eid)
        #expect(dto.title == "Gala")
        #expect(dto.eventDate.value == SupabaseTimestamp.date(from: "2026-06-04T16:00:00Z"))
    }
}
