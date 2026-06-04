import Foundation
import Models
import Services
@testable import shiftTimeline
import SwiftData
import Testing

@Suite("EventModel ↔ EventDTO mapping")
@MainActor
struct EventMappingTests {

    private func makeEvent(in context: ModelContext) throws -> (EventModel, WeatherSnapshot, PostEventReport) {
        let snapshot = WeatherSnapshot(
            entries: [BlockRainEntry(blockId: UUID(), rainProbability: 0.5)],
            fetchedAt: fixedTimestamp
        )
        let report = PostEventReport(entries: [], totalDriftMinutes: 7, totalShiftCount: 2, generatedAt: fixedTimestamp)
        let event = EventModel(
            title: "Beach Wedding",
            date: fixedTimestamp,
            latitude: 37.7749,
            longitude: -122.4194,
            venueNames: ["Cove", "Cliff House"],
            sunsetTime: fixedTimestamp,
            goldenHourStart: fixedTimestamp,
            status: .live
        )
        context.insert(event)
        event.weatherSnapshot = try JSONEncoder().encode(snapshot)
        event.wentLiveAt = fixedTimestamp
        event.completedAt = fixedTimestamp
        event.postEventReport = report
        return (event, snapshot, report)
    }

    @Test("forward: projects scalars and the supplied owner id")
    func forward() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let (event, snapshot, report) = try makeEvent(in: context)
        let ownerID = UUID()

        let dto = event.toDTO(ownerID: ownerID)

        #expect(dto.id == event.id)
        #expect(dto.ownerID == ownerID)
        #expect(dto.title == "Beach Wedding")
        #expect(dto.date.value == fixedTimestamp)
        #expect(dto.latitude == 37.7749)
        #expect(dto.longitude == -122.4194)
        #expect(dto.venueNames == ["Cove", "Cliff House"])
        #expect(dto.sunsetTime?.value == fixedTimestamp)
        #expect(dto.status == "live")
        #expect(dto.wentLiveAt?.value == fixedTimestamp)
        #expect(dto.completedAt?.value == fixedTimestamp)
        #expect(dto.weatherSnapshot == snapshot)
        #expect(dto.postEventReport == report)
        // Server-managed / non-local columns are not invented.
        #expect(dto.lastShiftedAt == nil)
        #expect(dto.createdAt == nil)
        #expect(dto.updatedAt == nil)
    }

    @Test("round-trip: model → DTO → model preserves scalars")
    func roundTrip() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let (event, snapshot, report) = try makeEvent(in: context)

        let model = event.toDTO(ownerID: UUID()).makeModel()

        #expect(model.id == event.id)
        #expect(model.title == event.title)
        #expect(model.date == event.date)
        #expect(model.latitude == event.latitude)
        #expect(model.longitude == event.longitude)
        #expect(model.venueNames == event.venueNames)
        #expect(model.sunsetTime == event.sunsetTime)
        #expect(model.goldenHourStart == event.goldenHourStart)
        #expect(model.status == .live)
        #expect(model.wentLiveAt == event.wentLiveAt)
        #expect(model.completedAt == event.completedAt)
        #expect(model.postEventReport == report)
        let decoded = try #require(model.weatherSnapshot).map {
            try JSONDecoder().decode(WeatherSnapshot.self, from: $0)
        }
        #expect(decoded == snapshot)
    }

    @Test("backward: an unknown status string falls back to .planning")
    func unknownStatusFallback() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let (event, _, _) = try makeEvent(in: context)
        var dto = event.toDTO(ownerID: UUID())
        dto = EventDTO(id: dto.id, ownerID: dto.ownerID, title: dto.title, date: dto.date, status: "bogus")
        #expect(dto.makeModel().status == .planning)
    }
}
