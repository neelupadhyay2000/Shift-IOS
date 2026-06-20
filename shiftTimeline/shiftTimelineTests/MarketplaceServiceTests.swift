import Foundation
import Models
@testable import shiftTimeline
import Testing

@Suite("SupabaseMarketplaceService — query / payload construction")
struct MarketplaceServiceTests {

    let profileID = UUID()

    // MARK: search_vendors params

    @Test("search params map category to raw value and pass coordinates through")
    func searchParamsMapsFields() {
        let params = SupabaseMarketplaceService.searchParams(
            query: "golden",
            category: .photographer,
            latitude: 43.65,
            longitude: -79.38,
            radiusKm: 50,
            limit: 20,
            offset: 40
        )
        #expect(params.pQuery == "golden")
        #expect(params.pCategory == "photographer")
        #expect(params.pLat == 43.65)
        #expect(params.pRadiusKm == 50)
        #expect(params.pLimit == 20)
        #expect(params.pOffset == 40)
    }

    @Test("blank query and nil category collapse to nil (no filter)")
    func searchParamsCollapsesEmpties() {
        let params = SupabaseMarketplaceService.searchParams(
            query: "   ", category: nil, latitude: nil, longitude: nil,
            radiusKm: nil, limit: 20, offset: -5
        )
        #expect(params.pQuery == nil)
        #expect(params.pCategory == nil)
        #expect(params.pOffset == 0)   // clamped
    }

    @Test("search params encode to the snake_case p_ wire keys")
    func searchParamsEncodeKeys() throws {
        let params = SupabaseMarketplaceService.searchParams(
            query: "x", category: .dj, latitude: 1, longitude: 2,
            radiusKm: 3, limit: 10, offset: 0
        )
        let json = try jsonObject(from: params)
        #expect(json["p_query"] as? String == "x")
        #expect(json["p_category"] as? String == "dj")
        #expect(json["p_lat"] != nil)
        #expect(json["p_radius_km"] != nil)
        #expect(json["p_limit"] as? Int == 10)
    }

    // MARK: search_name

    @Test("search_name lowercases and trims; empty becomes nil")
    func searchNameNormalizes() {
        #expect(SupabaseMarketplaceService.searchName(forBusinessName: "  Golden Hour  ") == "golden hour")
        #expect(SupabaseMarketplaceService.searchName(forBusinessName: "   ") == nil)
    }

    // MARK: category resolution

    @Test("custom category rides the free-text label when provided")
    func resolvedCustomCategory() {
        #expect(SupabaseMarketplaceService.resolvedCategory(.custom, customLabel: "Videographer") == "Videographer")
        #expect(SupabaseMarketplaceService.resolvedCategory(.custom, customLabel: "  ") == "custom")
        #expect(SupabaseMarketplaceService.resolvedCategory(.florist, customLabel: "ignored") == "florist")
    }

    // MARK: vendor profile payload

    @Test("vendor profile payload derives search_name and lowercases skills")
    func vendorPayloadDerivation() {
        let input = VendorProfileInput(
            businessName: "Golden Hour Studios",
            category: .photographer,
            skills: ["Wedding", " Portrait ", ""],
            serviceArea: "Toronto, ON",
            latitude: 43.65,
            longitude: -79.38,
            serviceRadiusKm: 80,
            isListed: true
        )
        let payload = SupabaseMarketplaceService.vendorProfilePayload(profileID: profileID, input: input)
        #expect(payload.profileID == profileID)
        #expect(payload.category == "photographer")
        #expect(payload.searchName == "golden hour studios")
        #expect(payload.skills == ["wedding", "portrait"])   // trimmed, lowercased, empties dropped
        #expect(payload.serviceArea == "Toronto, ON")
        #expect(payload.isListed)
    }

    @Test("identity payload nils-out empty fields so blanks don't persist")
    func identityPayloadNilsEmpties() {
        let input = VendorProfileInput(businessName: "  ", bio: "Hello", avatarURL: nil)
        let payload = SupabaseMarketplaceService.identityPayload(input)
        #expect(payload.businessName == nil)
        #expect(payload.bio == "Hello")
        #expect(payload.avatarURL == nil)
    }

    // MARK: storage MIME mapping

    @Test("file extension normalises and maps to the right MIME type")
    func mimeMapping() {
        #expect(SupabaseMarketplaceService.normalizedExtension("JPEG") == "jpg")
        #expect(SupabaseMarketplaceService.mimeType(for: "png") == "image/png")
        #expect(SupabaseMarketplaceService.mimeType(for: ".HEIC") == "image/heic")
        #expect(SupabaseMarketplaceService.mimeType(for: "webp") == "image/webp")
        #expect(SupabaseMarketplaceService.mimeType(for: "jpg") == "image/jpeg")
    }
}
