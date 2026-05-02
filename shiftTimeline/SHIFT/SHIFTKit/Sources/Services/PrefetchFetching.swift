import Foundation
import Models

/// Abstracts sunset data fetching so `SunsetPrefetchTask` can be tested
/// with a mock instead of hitting the live sunrise-sunset.org API.
public protocol SunsetFetching: Sendable {
    @MainActor
    func fetchIfNeeded(for event: EventModel) async -> SunsetResult?
}

/// Abstracts weather data fetching so `SunsetPrefetchTask` can be tested
/// with a mock instead of hitting WeatherKit.
public protocol WeatherFetching: Sendable {
    @MainActor
    func fetchIfNeeded(for event: EventModel) async -> WeatherSnapshot?
}

extension SunsetService: SunsetFetching {}
extension WeatherService: WeatherFetching {}
