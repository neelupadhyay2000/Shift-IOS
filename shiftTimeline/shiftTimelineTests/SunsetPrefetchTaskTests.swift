import Foundation
import Models
import Services
import SwiftData
import Testing
@testable import shiftTimeline

// MARK: - Mock Services

@MainActor
final class MockSunsetService: SunsetFetching {
    private(set) var fetchedEvents: [EventModel] = []
    private let stubbedResult: SunsetResult?

    init(result: SunsetResult? = SunsetResult(sunset: .now, goldenHourStart: .now)) {
        stubbedResult = result
    }

    func fetchIfNeeded(for event: EventModel) async -> SunsetResult? {
        fetchedEvents.append(event)
        if let result = stubbedResult {
            event.sunsetTime = result.sunset
            event.goldenHourStart = result.goldenHourStart
        }
        return stubbedResult
    }
}

@MainActor
final class MockWeatherService: WeatherFetching {
    private(set) var fetchedEvents: [EventModel] = []
    private let stubbedSnapshot: WeatherSnapshot?

    init(snapshot: WeatherSnapshot? = WeatherSnapshot(entries: [], fetchedAt: .now)) {
        stubbedSnapshot = snapshot
    }

    func fetchIfNeeded(for event: EventModel) async -> WeatherSnapshot? {
        fetchedEvents.append(event)
        if let snap = stubbedSnapshot {
            event.weatherSnapshot = try? JSONEncoder().encode(snap)
        }
        return stubbedSnapshot
    }
}

// MARK: - Helpers

extension SunsetPrefetchTaskTests {
    @MainActor
    @discardableResult
    private func insertEvent(
        title: String,
        hoursFromNow: Double,
        in context: ModelContext
    ) -> EventModel {
        let event = EventModel(
            title: title,
            date: Date.now.addingTimeInterval(hoursFromNow * 3600),
            latitude: 40.7128,
            longitude: -74.0060
        )
        context.insert(event)
        return event
    }
}

// MARK: - Tests

@Suite("SunsetPrefetchTask")
struct SunsetPrefetchTaskTests {

    @Test @MainActor
    func bothServicesAreCalledForEachQualifyingEvent() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        insertEvent(title: "Wedding", hoursFromNow: 6, in: context)
        insertEvent(title: "Concert", hoursFromNow: 24, in: context)
        try context.save()

        let sunsetMock = MockSunsetService()
        let weatherMock = MockWeatherService()

        await SunsetPrefetchTask.prefetchData(
            context: context,
            sunsetService: sunsetMock,
            weatherService: weatherMock
        )

        #expect(sunsetMock.fetchedEvents.count == 2)
        #expect(weatherMock.fetchedEvents.count == 2)
    }

    @Test @MainActor
    func weatherFetchRunsEvenWhenSunsetReturnsNil() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        insertEvent(title: "Wedding", hoursFromNow: 6, in: context)
        try context.save()

        // Sunset returns nil (simulates offline or missing coordinates)
        let sunsetMock = MockSunsetService(result: nil)
        let weatherMock = MockWeatherService()

        await SunsetPrefetchTask.prefetchData(
            context: context,
            sunsetService: sunsetMock,
            weatherService: weatherMock
        )

        #expect(weatherMock.fetchedEvents.count == 1)
    }

    @Test @MainActor
    func eventsOutside48HourWindowAreSkipped() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        insertEvent(title: "Far Future", hoursFromNow: 72, in: context)
        try context.save()

        let sunsetMock = MockSunsetService()
        let weatherMock = MockWeatherService()

        await SunsetPrefetchTask.prefetchData(
            context: context,
            sunsetService: sunsetMock,
            weatherService: weatherMock
        )

        #expect(sunsetMock.fetchedEvents.count == 0)
        #expect(weatherMock.fetchedEvents.count == 0)
    }

    @Test @MainActor
    func weatherSnapshotIsPersistedToEventModel() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let event = insertEvent(title: "Wedding", hoursFromNow: 6, in: context)
        try context.save()

        let snapshot = WeatherSnapshot(
            entries: [BlockRainEntry(blockId: UUID(), rainProbability: 0.7)],
            fetchedAt: .now
        )
        let weatherMock = MockWeatherService(snapshot: snapshot)

        await SunsetPrefetchTask.prefetchData(
            context: context,
            sunsetService: MockSunsetService(),
            weatherService: weatherMock
        )

        #expect(event.weatherSnapshot != nil)
    }

    @Test @MainActor
    func noFetchesOccurWhenNoEventsQualify() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let sunsetMock = MockSunsetService()
        let weatherMock = MockWeatherService()

        await SunsetPrefetchTask.prefetchData(
            context: context,
            sunsetService: sunsetMock,
            weatherService: weatherMock
        )

        #expect(sunsetMock.fetchedEvents.count == 0)
        #expect(weatherMock.fetchedEvents.count == 0)
    }
}
