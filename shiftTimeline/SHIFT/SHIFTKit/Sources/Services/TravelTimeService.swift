import CoreLocation
import Foundation
import MapKit

// MARK: - Protocol

public protocol DirectionsProviding: Sendable {
    func calculateETA(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> TimeInterval
}

// MARK: - Errors

public enum TravelTimeError: Error, Sendable, Equatable {
    case noRouteFound
    case networkUnavailable
}

// MARK: - Service

public actor TravelTimeService {

    private var cache: [String: Int] = [:]
    private let directionsProvider: any DirectionsProviding

    public init(directionsProvider: any DirectionsProviding = MapKitDirectionsProvider()) {
        self.directionsProvider = directionsProvider
    }

    /// Returns estimated driving time in minutes (rounded up) between two coordinates.
    /// Results are cached per coordinate pair (rounded to 4 decimal places) to avoid redundant API calls.
    public func travelTime(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> Int {
        let key = cacheKey(from: origin, to: destination)
        if let cached = cache[key] {
            return cached
        }

        let seconds = try await directionsProvider.calculateETA(from: origin, to: destination)
        let minutes = Int(ceil(seconds / 60.0))
        cache[key] = minutes
        return minutes
    }

    private func cacheKey(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) -> String {
        String(
            format: "%.4f,%.4f_%.4f,%.4f",
            origin.latitude, origin.longitude,
            destination.latitude, destination.longitude
        )
    }
}

// MARK: - MapKit Provider

public struct MapKitDirectionsProvider: DirectionsProviding {

    public init() {}

    public func calculateETA(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> TimeInterval {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile

        let directions = MKDirections(request: request)
        let response: MKDirections.Response
        do {
            response = try await directions.calculate()
        } catch {
            if (error as NSError).domain == NSURLErrorDomain {
                throw TravelTimeError.networkUnavailable
            }
            throw TravelTimeError.noRouteFound
        }

        guard let route = response.routes.first else {
            throw TravelTimeError.noRouteFound
        }

        return route.expectedTravelTime
    }
}
