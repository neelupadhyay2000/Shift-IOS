import Foundation
import Models
import Testing
@testable import shiftTimeline

/// Locks the wire contract for the Community Templates data layer (E23): RPC-row
/// decoding, the `Template` bridge, category fallback, and the RPC param encoding
/// (snake_case keys; optional args omitted so the SQL defaults apply).
@Suite("Community templates")
struct CommunityTemplateTests {

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    // MARK: - Decode

    @Test func decodesSearchRowAndBridgesToTemplate() throws {
        let id = UUID()
        let authorID = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "author_id": "\(authorID.uuidString)",
          "author_name": "Ava Author",
          "name": "Coastal Elopement",
          "description": "A small beach wedding",
          "category": "wedding",
          "blocks": [
            {"title":"Ceremony","relativeStartOffset":0,"duration":1800,"isPinned":true,"colorTag":"#FF9500","icon":"heart.fill"},
            {"title":"Toasts","relativeStartOffset":1800,"duration":900,"isPinned":false,"colorTag":"#007AFF","icon":"mic.fill"}
          ],
          "block_count": 2,
          "source_event_completed": true,
          "times_applied": 23,
          "created_at": "2026-06-25T12:00:00Z"
        }
        """
        let dto = try decoder.decode(CommunityTemplateDTO.self, from: Data(json.utf8))

        #expect(dto.id == id)
        #expect(dto.authorID == authorID)
        #expect(dto.authorName == "Ava Author")
        #expect(dto.category == "wedding")
        #expect(dto.blockCount == 2)
        #expect(dto.blocks.count == 2)
        #expect(dto.blocks.first?.title == "Ceremony")
        #expect(dto.blocks.first?.isPinned == true)
        #expect(dto.sourceEventCompleted)
        #expect(dto.timesApplied == 23)

        // Bridge: the DTO id carries through so apply can report it for the counter.
        #expect(dto.templateCategory == .wedding)
        #expect(dto.asTemplate.id == id)
        #expect(dto.asTemplate.name == "Coastal Elopement")
        #expect(dto.asTemplate.blocks.count == 2)

        // No `is_official` key in this payload — a project that hasn't run the
        // 20260709210000 migration must still decode, reading as not-official.
        #expect(dto.isOfficial == false)
        #expect(dto.hasApplies)
    }

    // MARK: - Official flag

    /// `is_official` (authorship: SHIFT wrote it) and `source_event_completed`
    /// (provenance: it came from an event actually run) are independent claims.
    /// A seeded first-party template asserts the first and not the second, so the
    /// two must never be conflated in the decode.
    @Test("an official template decodes as official without claiming verified")
    func officialIsIndependentOfVerified() throws {
        let json = officialTemplateJSON(isOfficial: true, verified: false, timesApplied: 0)
        let dto = try decoder.decode(CommunityTemplateDTO.self, from: Data(json.utf8))

        #expect(dto.isOfficial)
        #expect(dto.sourceEventCompleted == false)
    }

    @Test("an official template published from a completed event carries both")
    func officialCanAlsoBeVerified() throws {
        let json = officialTemplateJSON(isOfficial: true, verified: true, timesApplied: 5)
        let dto = try decoder.decode(CommunityTemplateDTO.self, from: Data(json.utf8))

        #expect(dto.isOfficial)
        #expect(dto.sourceEventCompleted)
    }

    /// The apply counter is suppressed at zero: a never-applied template shows
    /// nothing rather than a bare "0", which reads as a failure state. This is the
    /// reason the seed script can honestly leave `times_applied` at its default
    /// instead of fabricating a number.
    @Test("the apply counter is hidden until a template is actually applied")
    func applyCounterHiddenAtZero() throws {
        let unused = try decoder.decode(
            CommunityTemplateDTO.self,
            from: Data(officialTemplateJSON(isOfficial: true, verified: false, timesApplied: 0).utf8)
        )
        let used = try decoder.decode(
            CommunityTemplateDTO.self,
            from: Data(officialTemplateJSON(isOfficial: true, verified: false, timesApplied: 1).utf8)
        )

        #expect(unused.hasApplies == false)
        #expect(used.hasApplies)
    }

    private func officialTemplateJSON(
        isOfficial: Bool,
        verified: Bool,
        timesApplied: Int
    ) -> String {
        """
        {
          "id": "\(UUID().uuidString)",
          "author_id": "\(UUID().uuidString)",
          "author_name": "SHIFT",
          "name": "Charity Gala & Live Auction",
          "description": "A fundraising dinner",
          "category": "social",
          "blocks": [
            {"title":"Live Auction","relativeStartOffset":0,"duration":2700,"isPinned":true,"colorTag":"#FF3B30","icon":"dollarsign.circle.fill"}
          ],
          "block_count": 1,
          "source_event_completed": \(verified),
          "is_official": \(isOfficial),
          "times_applied": \(timesApplied),
          "created_at": "2026-07-09T12:00:00Z"
        }
        """
    }

    @Test func unknownCategoryFallsBackToSocial() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "author_id": "\(UUID().uuidString)",
          "author_name": "X",
          "name": "Mystery",
          "description": "",
          "category": "mystery",
          "blocks": [],
          "block_count": 0,
          "source_event_completed": false,
          "times_applied": 0,
          "created_at": "2026-06-25T12:00:00Z"
        }
        """
        let dto = try decoder.decode(CommunityTemplateDTO.self, from: Data(json.utf8))
        #expect(dto.templateCategory == .social)
    }

    @Test func decodesRawRowWithStatusFields() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "author_id": "\(UUID().uuidString)",
          "name": "Mine",
          "description": "",
          "category": "corporate",
          "blocks": [],
          "block_count": 0,
          "source_event_completed": false,
          "times_applied": 4,
          "is_published": false,
          "created_at": "2026-06-25T12:00:00Z",
          "deleted_at": null
        }
        """
        let row = try decoder.decode(CommunityTemplateRowDTO.self, from: Data(json.utf8))
        #expect(row.isPublished == false)
        #expect(row.timesApplied == 4)
        #expect(row.templateCategory == .corporate)
    }

    // MARK: - Encode (RPC params)

    @Test func searchParamsUseWireKeysAndOmitNilCategory() throws {
        let params = SearchCommunityTemplatesParams(
            pCategory: nil, pQuery: "beach", pSort: "popular", pLimit: 30, pOffset: 0
        )
        let obj = try jsonObject(params)
        // nil category is not sent, so the RPC's default (no filter) applies.
        #expect(obj["p_category"] as? String == nil)
        #expect(obj["p_query"] as? String == "beach")
        #expect(obj["p_sort"] as? String == "popular")
        #expect(obj["p_limit"] as? Int == 30)
        #expect(obj["p_offset"] as? Int == 0)
    }

    @Test func searchParamsIncludeCategoryWhenSet() throws {
        let params = SearchCommunityTemplatesParams(
            pCategory: "wedding", pQuery: "", pSort: "newest", pLimit: 60, pOffset: 0
        )
        let obj = try jsonObject(params)
        #expect(obj["p_category"] as? String == "wedding")
        #expect(obj["p_sort"] as? String == "newest")
    }

    @Test func publishParamsOmitNilSourceEvent() throws {
        let params = PublishCommunityTemplateParams(
            pName: "N", pDescription: "", pCategory: "social",
            pBlocks: [TemplateBlock(title: "a", relativeStartOffset: 0, duration: 60)],
            pBlockCount: 1, pSourceEventID: nil
        )
        let obj = try jsonObject(params)
        #expect(obj["p_source_event_id"] as? String == nil)   // unverified publish
        #expect(obj["p_name"] as? String == "N")
        #expect(obj["p_category"] as? String == "social")
        #expect((obj["p_blocks"] as? [Any])?.count == 1)
    }

    @Test func publishParamsIncludeSourceEventWhenSet() throws {
        let eventID = UUID()
        let params = PublishCommunityTemplateParams(
            pName: "N", pDescription: "d", pCategory: "wedding",
            pBlocks: [], pBlockCount: 0, pSourceEventID: eventID
        )
        let obj = try jsonObject(params)
        #expect(obj["p_source_event_id"] as? String == eventID.uuidString)
    }

    @Test func sortRawValuesMatchSQL() {
        #expect(CommunityTemplateSort.popular.rawValue == "popular")
        #expect(CommunityTemplateSort.newest.rawValue == "newest")
    }

    // MARK: - Helpers

    private func jsonObject(_ value: some Encodable) throws -> [String: Any] {
        let data = try encoder.encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
