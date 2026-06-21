import Foundation
@testable import shiftTimeline
import Testing

@Suite("RequestThreadLive — merge / dedupe")
@MainActor
struct RequestMessagingTests {

    private let requestID = UUID()

    private func message(_ id: UUID = UUID(), at seconds: TimeInterval, body: String = "hi") -> RequestMessageDTO {
        RequestMessageDTO(
            id: id, requestID: requestID, senderID: UUID(), body: body,
            createdAt: PostgresTimestamp(Date(timeIntervalSince1970: 1_780_000_000 + seconds))
        )
    }

    @Test("applying a new message appends and keeps created_at order")
    func appendsInOrder() {
        let a = message(at: 10)
        let b = message(at: 0)
        var buf = RequestThreadLive.merged([], with: a)
        buf = RequestThreadLive.merged(buf, with: b)
        #expect(buf.map(\.id) == [b.id, a.id])   // sorted oldest→newest
    }

    @Test("applying the same id twice dedupes (optimistic then echo)")
    func dedupesById() {
        let id = UUID()
        let optimistic = message(id, at: 5, body: "sending")
        let echo = message(id, at: 5, body: "sending")
        var buf = RequestThreadLive.merged([], with: optimistic)
        buf = RequestThreadLive.merged(buf, with: echo)
        #expect(buf.count == 1)
    }

    @Test("a duplicate id replaces the existing entry (server canonical wins)")
    func duplicateReplaces() {
        let id = UUID()
        let optimistic = message(id, at: 5, body: "draft")
        let confirmed = message(id, at: 5, body: "draft")
        var buf = RequestThreadLive.merged([], with: optimistic)
        buf = RequestThreadLive.merged(buf, with: confirmed)
        #expect(buf.count == 1)
        #expect(buf.first?.body == "draft")
    }

    @Test("page merge unions by id and sorts; existing wins on conflict")
    func pageMergeUnions() {
        let shared = UUID()
        let existing = [message(shared, at: 5, body: "keep"), message(at: 9)]
        let page = [message(shared, at: 5, body: "fetched"), message(at: 1)]
        let merged = RequestThreadLive.merged(existing, withPage: page)
        #expect(merged.count == 3)
        #expect(merged.first?.createdAt.value == Date(timeIntervalSince1970: 1_780_000_001))
        #expect(merged.first(where: { $0.id == shared })?.body == "keep")  // existing wins
    }

    @Test("DTO decodes a realtime/REST snake_case record")
    func dtoDecodes() throws {
        let id = UUID(); let rid = UUID(); let sid = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "request_id": "\(rid.uuidString)",
            "sender_id": "\(sid.uuidString)",
            "body": "hello",
            "created_at": "2026-06-04T16:00:00Z"
        }
        """
        let dto = try decodeDTO(RequestMessageDTO.self, from: json)
        #expect(dto.id == id)
        #expect(dto.requestID == rid)
        #expect(dto.senderID == sid)
        #expect(dto.body == "hello")
    }

    @Test("insert payload encodes id/request_id/sender_id/body (no created_at)")
    func insertEncodes() throws {
        let payload = RequestMessageInsert(id: UUID(), requestID: requestID, senderID: UUID(), body: "yo")
        let json = try jsonObject(from: payload)
        #expect(json["id"] != nil)
        #expect(json["request_id"] != nil)
        #expect(json["sender_id"] != nil)
        #expect(json["body"] as? String == "yo")
        #expect(json["created_at"] == nil)
    }
}
