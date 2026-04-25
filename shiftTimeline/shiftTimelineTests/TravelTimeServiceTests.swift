import CoreLocation
import Foundation
import Services
import Testing

@Suite("Travel Time Service")
struct TravelTimeServiceTests {

    // MARK: - Mock

    /// Actor-based mock keeps state isolation explicit and avoids `@unchecked Sendable`.
    private actor MockDirectionsProvider: DirectionsProviding {
        var result: TimeInterval?
        var error: Error?
        private(set) var callCount = 0

        init(result: TimeInterval? = nil, error: Error? = nil) {
            self.result = result
            self.error = error
        }

        func setResult(_ value: TimeInterval?) { result = value }
        func setError(_ value: Error?) { error = value }

        func calculateETA(
            from origin: CLLocationCoordinate2D,
            to destination: CLLocationCoordinate2D
        ) async throws -> TimeInterval {
            callCount += 1
            if let error { throw error }
            guard let result else { throw TravelTimeError.noRouteFound }
            return result
        }
    }

    // MARK: - ETA Calculation

    @Test func returnsETAInMinutesRoundedUp() async throws {
        let mock = MockDirectionsProvider(result: 754) // 12.57 min → rounds up to 13
        let service = TravelTimeService(directionsProvider: mock)

        let minutes = try await service.travelTime(
            from: CLLocationCoordinate2D(latitude: 37.3318, longitude: -122.0312),
            to: CLLocationCoordinate2D(latitude: 37.3382, longitude: -122.0241)
        )

        #expect(minutes == 13)
    }

    @Test func returnsExactMinutesWithoutExtraRounding() async throws {
        let mock = MockDirectionsProvider(result: 600) // exactly 10 min
        let service = TravelTimeService(directionsProvider: mock)

        let minutes = try await service.travelTime(
            from: CLLocationCoordinate2D(latitude: 37.3318, longitude: -122.0312),
            to: CLLocationCoordinate2D(latitude: 37.3382, longitude: -122.0241)
        )

        #expect(minutes == 10)
    }

    // MARK: - Caching

    @Test func cachesResultForSameCoordinatePair() async throws {
        let mock = MockDirectionsProvider(result: 600)
        let service = TravelTimeService(directionsProvider: mock)

        let origin = CLLocationCoordinate2D(latitude: 37.3318, longitude: -122.0312)
        let destination = CLLocationCoordinate2D(latitude: 37.3382, longitude: -122.0241)

        let first = try await service.travelTime(from: origin, to: destination)
        let second = try await service.travelTime(from: origin, to: destination)

        #expect(first == second)
        let calls = await mock.callCount
        #expect(calls == 1, "second call should use cache, not API")
    }

    @Test func differentCoordinatePairsNotCachedTogether() async throws {
        let mock = MockDirectionsProvider(result: 600)
        let service = TravelTimeService(directionsProvider: mock)

        _ = try await service.travelTime(
            from: CLLocationCoordinate2D(latitude: 37.3318, longitude: -122.0312),
            to: CLLocationCoordinate2D(latitude: 37.3382, longitude: -122.0241)
        )
        _ = try await service.travelTime(
            from: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            to: CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)
        )

        let calls = await mock.callCount
        #expect(calls == 2, "different coordinate pairs must not share cache")
    }

    @Test func nearbyCoordinatesRoundToSameCacheKey() async throws {
        let mock = MockDirectionsProvider(result: 600)
        let service = TravelTimeService(directionsProvider: mock)

        // Coordinates differ only at the 5th decimal place and both round down to the same 4dp key
        _ = try await service.travelTime(
            from: CLLocationCoordinate2D(latitude: 37.33182, longitude: -122.03122),
            to: CLLocationCoordinate2D(latitude: 37.33822, longitude: -122.02412)
        )
        _ = try await service.travelTime(
            from: CLLocationCoordinate2D(latitude: 37.33184, longitude: -122.03124),
            to: CLLocationCoordinate2D(latitude: 37.33824, longitude: -122.02414)
        )

        let calls = await mock.callCount
        #expect(calls == 1, "coordinates rounding to same 4dp key should share cache")
    }

    // MARK: - Error Handling

    @Test func throwsNoRouteFoundError() async {
        let mock = MockDirectionsProvider(error: TravelTimeError.noRouteFound)
        let service = TravelTimeService(directionsProvider: mock)

        await #expect(throws: TravelTimeError.noRouteFound) {
            try await service.travelTime(
                from: CLLocationCoordinate2D(latitude: 37.3318, longitude: -122.0312),
                to: CLLocationCoordinate2D(latitude: 37.3382, longitude: -122.0241)
            )
        }
    }

    @Test func throwsNetworkUnavailableError() async {
        let mock = MockDirectionsProvider(error: TravelTimeError.networkUnavailable)
        let service = TravelTimeService(directionsProvider: mock)

        await #expect(throws: TravelTimeError.networkUnavailable) {
            try await service.travelTime(
                from: CLLocationCoordinate2D(latitude: 37.3318, longitude: -122.0312),
                to: CLLocationCoordinate2D(latitude: 37.3382, longitude: -122.0241)
            )
        }
    }

    @Test func errorResponsesAreNotCached() async throws {
        let mock = MockDirectionsProvider(error: TravelTimeError.noRouteFound)
        let service = TravelTimeService(directionsProvider: mock)

        let origin = CLLocationCoordinate2D(latitude: 37.3318, longitude: -122.0312)
        let destination = CLLocationCoordinate2D(latitude: 37.3382, longitude: -122.0241)

        // First call fails
        _ = try? await service.travelTime(from: origin, to: destination)

        // Fix the mock — second call should retry
        await mock.setError(nil)
        await mock.setResult(600)

        let minutes = try await service.travelTime(from: origin, to: destination)

        #expect(minutes == 10)
        let calls = await mock.callCount
        #expect(calls == 2, "failed lookup must not be cached")
    }
}
