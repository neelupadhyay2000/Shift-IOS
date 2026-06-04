import Foundation
@testable import shiftTimeline
import Testing

@Suite("BlockDTO — coding")
struct BlockDTOTests {

    private func makeFull(id: UUID = UUID()) -> BlockDTO {
        BlockDTO(
            id: id,
            trackID: UUID(),
            eventID: UUID(),
            title: "Ceremony",
            scheduledStart: fixedPGTimestamp,
            originalStart: fixedPGTimestamp,
            duration: 1800,
            minimumDuration: 900,
            isPinned: true,
            notes: "Bring the rings",
            voiceMemoPath: "abc/def.m4a",
            voiceMemoDuration: 12.5,
            voiceMemoCreatedAt: fixedPGTimestamp,
            colorTag: "#FF0000",
            icon: "heart.fill",
            status: "active",
            requiresReview: true,
            isOutdoor: true,
            venueAddress: "123 Main St",
            venueName: "St. Mary's",
            blockLatitude: 37.0,
            blockLongitude: -122.0,
            isTransitBlock: false,
            completedTime: fixedPGTimestamp,
            createdAt: fixedPGTimestamp,
            updatedAt: fixedPGTimestamp,
            deletedAt: nil
        )
    }

    @Test("encodes all multi-word columns in snake_case")
    func encodesSnakeCaseKeys() throws {
        let json = try jsonObject(from: makeFull())
        for key in [
            "track_id", "event_id", "scheduled_start", "original_start",
            "minimum_duration", "is_pinned", "voice_memo_path", "voice_memo_duration",
            "voice_memo_created_at", "color_tag", "requires_review", "is_outdoor",
            "venue_address", "venue_name", "block_latitude", "block_longitude",
            "is_transit_block", "completed_time", "created_at", "updated_at",
        ] {
            #expect(json[key] != nil, "missing snake_case key \(key)")
        }
        #expect(json["trackId"] == nil)
        #expect(json["scheduledStart"] == nil)
    }

    @Test("encodes status as raw text and numeric columns as numbers")
    func encodesScalarTypes() throws {
        let json = try jsonObject(from: makeFull())
        #expect(json["status"] as? String == "active")
        #expect(json["duration"] as? Double == 1800)
        #expect(json["minimum_duration"] as? Double == 900)
        #expect(json["is_pinned"] as? Bool == true)
        #expect(json["scheduled_start"] as? String != nil)
    }

    @Test("omits nil optional columns")
    func omitsNilColumns() throws {
        let dto = BlockDTO(
            id: UUID(),
            trackID: UUID(),
            eventID: UUID(),
            title: "Bare",
            scheduledStart: fixedPGTimestamp,
            originalStart: fixedPGTimestamp,
            duration: 600,
            minimumDuration: 0,
            isPinned: false,
            notes: "",
            colorTag: "#007AFF",
            icon: "circle.fill",
            status: "upcoming",
            requiresReview: false,
            isOutdoor: false,
            venueAddress: "",
            venueName: "",
            isTransitBlock: false
        )
        let json = try jsonObject(from: dto)
        #expect(json["voice_memo_path"] == nil)
        #expect(json["voice_memo_duration"] == nil)
        #expect(json["voice_memo_created_at"] == nil)
        #expect(json["block_latitude"] == nil)
        #expect(json["block_longitude"] == nil)
        #expect(json["completed_time"] == nil)
        #expect(json["created_at"] == nil)
        #expect(json["deleted_at"] == nil)
    }

    @Test("decodes a Postgres-style row, mapping a null optional to nil")
    func decodesPostgresRow() throws {
        let id = UUID()
        let trackID = UUID()
        let eventID = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "track_id": "\(trackID.uuidString)",
            "event_id": "\(eventID.uuidString)",
            "title": "Toasts",
            "scheduled_start": "2026-06-04T19:00:00+00:00",
            "original_start": "2026-06-04T19:00:00+00:00",
            "duration": 1200,
            "minimum_duration": 600,
            "is_pinned": false,
            "notes": "",
            "voice_memo_path": null,
            "color_tag": "#34C759",
            "icon": "mic.fill",
            "status": "upcoming",
            "requires_review": false,
            "is_outdoor": false,
            "venue_address": "",
            "venue_name": "",
            "is_transit_block": false
        }
        """
        let dto = try decodeDTO(BlockDTO.self, from: json)
        #expect(dto.id == id)
        #expect(dto.trackID == trackID)
        #expect(dto.eventID == eventID)
        #expect(dto.duration == 1200)
        #expect(dto.status == "upcoming")
        #expect(dto.voiceMemoPath == nil)
        #expect(dto.blockLatitude == nil)
        #expect(dto.scheduledStart.value == SupabaseTimestamp.date(from: "2026-06-04T19:00:00Z"))
    }

    @Test("round-trips full and minimal DTOs")
    func roundTrips() throws {
        let full = makeFull()
        #expect(try roundTrip(full) == full)
    }
}
