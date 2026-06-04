import Foundation
@testable import shiftTimeline
import Testing

@Suite("BlockVendorDTO — coding")
struct BlockVendorDTOTests {

    @Test("encodes composite-key columns in snake_case")
    func encodesSnakeCaseKeys() throws {
        let dto = BlockVendorDTO(blockID: UUID(), eventVendorID: UUID(), eventID: UUID())
        let json = try jsonObject(from: dto)
        #expect(json["block_id"] != nil)
        #expect(json["event_vendor_id"] != nil)
        #expect(json["event_id"] != nil)
        // No updated_at on this junction table.
        #expect(json["updated_at"] == nil)
        #expect(json["created_at"] == nil)
    }

    @Test("decodes a Postgres-style row")
    func decodesPostgresRow() throws {
        let blockID = UUID()
        let eventVendorID = UUID()
        let eventID = UUID()
        let json = """
        {
            "block_id": "\(blockID.uuidString)",
            "event_vendor_id": "\(eventVendorID.uuidString)",
            "event_id": "\(eventID.uuidString)",
            "created_at": "2026-06-04T16:00:00Z",
            "deleted_at": null
        }
        """
        let dto = try decodeDTO(BlockVendorDTO.self, from: json)
        #expect(dto.blockID == blockID)
        #expect(dto.eventVendorID == eventVendorID)
        #expect(dto.eventID == eventID)
        #expect(dto.deletedAt == nil)
    }

    @Test("round-trips")
    func roundTrips() throws {
        let dto = BlockVendorDTO(
            blockID: UUID(),
            eventVendorID: UUID(),
            eventID: UUID(),
            createdAt: fixedPGTimestamp
        )
        #expect(try roundTrip(dto) == dto)
    }
}

@Suite("BlockDependencyDTO — coding")
struct BlockDependencyDTOTests {

    @Test("encodes directed-edge columns in snake_case")
    func encodesSnakeCaseKeys() throws {
        let dto = BlockDependencyDTO(blockID: UUID(), dependsOnBlockID: UUID(), eventID: UUID())
        let json = try jsonObject(from: dto)
        #expect(json["block_id"] != nil)
        #expect(json["depends_on_block_id"] != nil)
        #expect(json["event_id"] != nil)
        #expect(json["dependsOnBlockId"] == nil)
    }

    @Test("decodes a Postgres-style row")
    func decodesPostgresRow() throws {
        let blockID = UUID()
        let dependsOn = UUID()
        let eventID = UUID()
        let json = """
        {
            "block_id": "\(blockID.uuidString)",
            "depends_on_block_id": "\(dependsOn.uuidString)",
            "event_id": "\(eventID.uuidString)"
        }
        """
        let dto = try decodeDTO(BlockDependencyDTO.self, from: json)
        #expect(dto.blockID == blockID)
        #expect(dto.dependsOnBlockID == dependsOn)
        #expect(dto.eventID == eventID)
        #expect(dto.createdAt == nil)
    }

    @Test("round-trips")
    func roundTrips() throws {
        let dto = BlockDependencyDTO(blockID: UUID(), dependsOnBlockID: UUID(), eventID: UUID())
        #expect(try roundTrip(dto) == dto)
    }
}
