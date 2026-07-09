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
