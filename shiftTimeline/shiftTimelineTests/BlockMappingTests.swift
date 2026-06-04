import Foundation
import Models
import Services
@testable import shiftTimeline
import SwiftData
import Testing

@Suite("TimeBlockModel ↔ BlockDTO mapping")
@MainActor
struct BlockMappingTests {

    private func makeGraph(in context: ModelContext) -> (EventModel, TimelineTrack, TimeBlockModel) {
        let event = EventModel(title: "E", date: fixedTimestamp, latitude: 0, longitude: 0)
        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true)
        let block = TimeBlockModel(
            title: "Ceremony",
            scheduledStart: fixedTimestamp,
            originalStart: fixedTimestamp,
            duration: 1800,
            minimumDuration: 900,
            isPinned: true,
            notes: "Rings",
            voiceMemoURL: URL(string: "file:///memos/abc.m4a"),
            voiceMemoDuration: 8.5,
            voiceMemoCreatedAt: fixedTimestamp,
            colorTag: "#FF0000",
            icon: "heart.fill",
            status: .overtime,
            requiresReview: true
        )
        context.insert(event)
        context.insert(track)
        context.insert(block)
        track.event = event
        block.track = track
        block.isOutdoor = true
        block.venueAddress = "123 Main"
        block.venueName = "St. Mary's"
        block.blockLatitude = 37.0
        block.blockLongitude = -122.0
        block.isTransitBlock = false
        block.completedTime = fixedTimestamp
        return (event, track, block)
    }

    @Test("forward: scalars, track_id and denormalized event_id")
    func forward() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let (event, track, block) = makeGraph(in: context)

        let dto = try block.toDTO()
        #expect(dto.id == block.id)
        #expect(dto.trackID == track.id)
        #expect(dto.eventID == event.id)
        #expect(dto.title == "Ceremony")
        #expect(dto.scheduledStart.value == fixedTimestamp)
        #expect(dto.duration == 1800)
        #expect(dto.minimumDuration == 900)
        #expect(dto.status == "overtime")
        #expect(dto.voiceMemoPath == "file:///memos/abc.m4a")
        #expect(dto.voiceMemoDuration == 8.5)
        #expect(dto.blockLatitude == 37.0)
        #expect(dto.completedTime?.value == fixedTimestamp)
    }

    @Test("round-trip: model → DTO → model preserves scalars")
    func roundTrip() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let (_, _, block) = makeGraph(in: context)

        let model = try block.toDTO().makeModel()
        #expect(model.id == block.id)
        #expect(model.title == block.title)
        #expect(model.scheduledStart == block.scheduledStart)
        #expect(model.originalStart == block.originalStart)
        #expect(model.duration == block.duration)
        #expect(model.minimumDuration == block.minimumDuration)
        #expect(model.isPinned == block.isPinned)
        #expect(model.notes == block.notes)
        #expect(model.voiceMemoURL == block.voiceMemoURL)
        #expect(model.voiceMemoDuration == block.voiceMemoDuration)
        #expect(model.voiceMemoCreatedAt == block.voiceMemoCreatedAt)
        #expect(model.colorTag == block.colorTag)
        #expect(model.icon == block.icon)
        #expect(model.status == .overtime)
        #expect(model.requiresReview == block.requiresReview)
        #expect(model.isOutdoor == block.isOutdoor)
        #expect(model.venueAddress == block.venueAddress)
        #expect(model.venueName == block.venueName)
        #expect(model.blockLatitude == block.blockLatitude)
        #expect(model.blockLongitude == block.blockLongitude)
        #expect(model.isTransitBlock == block.isTransitBlock)
        #expect(model.completedTime == block.completedTime)
    }

    @Test("junctions: block_vendors and block_dependencies extracted by id")
    func junctions() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let (event, track, block) = makeGraph(in: context)
        let other = TimeBlockModel(title: "Setup", scheduledStart: fixedTimestamp, duration: 600)
        let vendor = VendorModel(name: "DJ", role: .dj)
        context.insert(other)
        context.insert(vendor)
        other.track = track
        vendor.event = event
        block.vendors = [vendor]
        block.dependencies = [other]

        let vendorJunctions = try block.blockVendorDTOs()
        #expect(vendorJunctions == [BlockVendorDTO(blockID: block.id, eventVendorID: vendor.id, eventID: event.id)])

        let dependencyJunctions = try block.blockDependencyDTOs()
        #expect(dependencyJunctions == [BlockDependencyDTO(blockID: block.id, dependsOnBlockID: other.id, eventID: event.id)])
    }

    @Test("forward: throws when the block is detached from track or event")
    func detachedThrows() throws {
        let detachedFromTrack = TimeBlockModel(title: "X", scheduledStart: fixedTimestamp, duration: 1)
        #expect(throws: ModelMappingError.missingTrack) {
            _ = try detachedFromTrack.toDTO()
        }

        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let trackWithoutEvent = TimelineTrack(name: "T", sortOrder: 0)
        let block = TimeBlockModel(title: "Y", scheduledStart: fixedTimestamp, duration: 1)
        context.insert(trackWithoutEvent)
        context.insert(block)
        block.track = trackWithoutEvent
        #expect(throws: ModelMappingError.missingEvent) {
            _ = try block.toDTO()
        }
    }
}
