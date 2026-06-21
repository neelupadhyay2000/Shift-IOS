import Foundation
@testable import shiftTimeline
import Testing

@Suite("ServiceRequestService — snapshot + payload construction")
struct ServiceRequestServiceTests {

    // MARK: requested_blocks snapshot builder (pure)

    @Test("builds a requested-block snapshot: end = start + duration")
    func snapshotComputesEnd() {
        let id = UUID()
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let sources = [
            ServiceRequestService.BlockSnapshotSource(id: id, title: "Ceremony", scheduledStart: start, duration: 1800),
        ]
        let blocks = ServiceRequestService.requestedBlocks(from: sources)
        #expect(blocks.count == 1)
        #expect(blocks[0].blockID == id)
        #expect(blocks[0].title == "Ceremony")
        #expect(blocks[0].start.value == start)
        #expect(blocks[0].end.value == start.addingTimeInterval(1800))
    }

    @Test("preserves input order and supports an empty selection")
    func snapshotOrderAndEmpty() {
        let a = UUID(); let b = UUID()
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let sources = [
            ServiceRequestService.BlockSnapshotSource(id: a, title: "A", scheduledStart: start, duration: 60),
            ServiceRequestService.BlockSnapshotSource(id: b, title: "B", scheduledStart: start, duration: 60),
        ]
        let blocks = ServiceRequestService.requestedBlocks(from: sources)
        #expect(blocks.map(\.blockID) == [a, b])
        #expect(ServiceRequestService.requestedBlocks(from: []).isEmpty)
    }

    // MARK: snapshot encodes to the jsonb element shape

    @Test("requested block encodes block_id/title/start/end in snake_case")
    func requestedBlockEncoding() throws {
        let id = UUID()
        let block = RequestedBlockDTO(
            blockID: id, title: "Reception",
            start: PostgresTimestamp(Date(timeIntervalSince1970: 1_780_000_000)),
            end: PostgresTimestamp(Date(timeIntervalSince1970: 1_780_003_600))
        )
        let json = try jsonObject(from: block)
        #expect(json["block_id"] as? String == id.uuidString)
        #expect(json["title"] as? String == "Reception")
        #expect(json["start"] != nil)
        #expect(json["end"] != nil)
        #expect(json["blockID"] == nil)
    }

    // MARK: insert payload

    @Test("insert payload encodes snake_case columns; nil note is omitted")
    func insertPayloadEncoding() throws {
        let payload = ServiceRequestInsert(
            eventID: UUID(), plannerID: UUID(), vendorProfileID: UUID(),
            note: nil, requestedBlocks: [], eventTitle: "Wedding",
            eventDate: PostgresTimestamp(Date(timeIntervalSince1970: 1_780_000_000))
        )
        let json = try jsonObject(from: payload)
        #expect(json["event_id"] != nil)
        #expect(json["planner_id"] != nil)
        #expect(json["vendor_profile_id"] != nil)
        #expect(json["event_title"] as? String == "Wedding")
        #expect(json["requested_blocks"] as? [Any] != nil)
        #expect(json["note"] == nil)            // nil omitted (synthesized encodeIfPresent)
        #expect(json["status"] == nil)          // server-defaulted
    }

    // MARK: RPC params + result decoding

    @Test("respond params encode the p_ wire keys")
    func respondParamsEncoding() throws {
        let params = RespondRequestParams(pRequestID: UUID(), pAccept: true, pMessage: "yes")
        let json = try jsonObject(from: params)
        #expect(json["p_request_id"] != nil)
        #expect(json["p_accept"] as? Bool == true)
        #expect(json["p_message"] as? String == "yes")
    }

    @Test("response DTO decodes the RPC row")
    func responseDecoding() throws {
        let ev = UUID()
        let req = UUID()
        let json = """
        { "request_id": "\(req.uuidString)", "status": "accepted", "event_vendor_id": "\(ev.uuidString)", "assigned_blocks_count": 3 }
        """
        let dto = try decodeDTO(ServiceRequestResponseDTO.self, from: json)
        #expect(dto.requestID == req)
        #expect(dto.status == "accepted")
        #expect(dto.eventVendorID == ev)
        #expect(dto.assignedBlocksCount == 3)
    }
}
