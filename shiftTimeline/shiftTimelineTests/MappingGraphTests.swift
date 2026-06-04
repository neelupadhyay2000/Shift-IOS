import Foundation
import Models
import Services
@testable import shiftTimeline
import SwiftData
import Testing

/// End-to-end relationship round-trip: a wired model graph is projected to DTOs
/// (relationships captured as foreign-key ids), then reconstructed in a fresh
/// store purely from those DTOs + id lookups, and the rebuilt graph must match
/// the original by id — including SwiftData's maintained inverses.
@Suite("DTO ↔ model graph mapping")
@MainActor
struct MappingGraphTests {

    @Test("full graph round-trips by id, including junctions and inverses")
    func graphRoundTrip() throws {
        // MARK: Original wired graph
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let event = EventModel(title: "Gala", date: fixedTimestamp, latitude: 1, longitude: 2)
        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true)
        let block = TimeBlockModel(title: "Ceremony", scheduledStart: fixedTimestamp, duration: 1800)
        let dependency = TimeBlockModel(title: "Setup", scheduledStart: fixedTimestamp, duration: 600)
        let vendor = VendorModel(name: "DJ", role: .dj)
        let record = ShiftRecord(timestamp: fixedTimestamp, deltaMinutes: 10, triggeredBy: .manual)
        context.insert(event)
        context.insert(track)
        context.insert(block)
        context.insert(dependency)
        context.insert(vendor)
        context.insert(record)
        track.event = event
        block.track = track
        dependency.track = track
        vendor.event = event
        block.vendors = [vendor]
        block.dependencies = [dependency]
        record.event = event
        record.sourceBlock = block

        // MARK: Forward — relationships become foreign-key ids
        let ownerID = UUID()
        let eDTO = event.toDTO(ownerID: ownerID)
        let tDTO = try track.toDTO()
        let bDTO = try block.toDTO()
        let depDTO = try dependency.toDTO()
        let vDTO = try vendor.toDTO()
        let sDTO = try record.toDTO()
        let vendorJunctions = try block.blockVendorDTOs()
        let dependencyJunctions = try block.blockDependencyDTOs()

        #expect(tDTO.eventID == event.id)
        #expect(bDTO.trackID == track.id)
        #expect(bDTO.eventID == event.id)
        #expect(depDTO.trackID == track.id)
        #expect(vDTO.eventID == event.id)
        #expect(sDTO.eventID == event.id)
        #expect(sDTO.sourceBlockID == block.id)
        #expect(vendorJunctions == [BlockVendorDTO(blockID: block.id, eventVendorID: vendor.id, eventID: event.id)])
        #expect(dependencyJunctions == [BlockDependencyDTO(blockID: block.id, dependsOnBlockID: dependency.id, eventID: event.id)])

        // MARK: Backward — reconstruct from DTOs only, in a clean store
        let storeContainer = try PersistenceController.forTesting()
        let store = storeContainer.mainContext
        let rEvent = eDTO.makeModel()
        let rTrack = tDTO.makeModel()
        let rBlock = bDTO.makeModel()
        let rDependency = depDTO.makeModel()
        let rVendor = vDTO.makeModel()
        let rRecord = sDTO.makeModel()
        store.insert(rEvent)
        store.insert(rTrack)
        store.insert(rBlock)
        store.insert(rDependency)
        store.insert(rVendor)
        store.insert(rRecord)

        let events = [rEvent.id: rEvent]
        let tracks = [rTrack.id: rTrack]
        let blocks = [rBlock.id: rBlock, rDependency.id: rDependency]
        let vendors = [rVendor.id: rVendor]

        tDTO.linkRelationships(rTrack, events: events)
        bDTO.linkParent(rBlock, tracks: tracks)
        depDTO.linkParent(rDependency, tracks: tracks)
        vDTO.linkRelationships(rVendor, events: events)
        sDTO.linkRelationships(rRecord, events: events, blocks: blocks)
        rBlock.linkVendors(vendorJunctions, vendors: vendors)
        rBlock.linkDependencies(dependencyJunctions, blocks: blocks)

        // MARK: Relationships reconstructed by id
        #expect(rTrack.event?.id == event.id)
        #expect(rBlock.track?.id == track.id)
        #expect(rBlock.track?.event?.id == event.id)
        #expect(rDependency.track?.id == track.id)
        #expect(rVendor.event?.id == event.id)
        #expect(rRecord.event?.id == event.id)
        #expect(rRecord.sourceBlock?.id == block.id)
        #expect(rBlock.vendors?.map(\.id) == [vendor.id])
        #expect(rBlock.dependencies?.map(\.id) == [dependency.id])
        // SwiftData maintains the inverse edge.
        #expect(rDependency.dependents?.map(\.id) == [block.id])
    }
}
