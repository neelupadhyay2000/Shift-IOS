import CoreLocation
import Foundation
import Models
import os
import WeatherKit

// Avoid name collision with WeatherKit.WeatherService (D5)
private typealias WKWeatherService = WeatherKit.WeatherService

/// Fetches hourly precipitation forecasts from Apple's WeatherKit API
/// and resolves per-block rain probabilities for a given event.
///
/// Results are cached on `EventModel.weatherSnapshot` as JSON-encoded `Data`.
/// The cache is considered fresh for 30 minutes; `fetchIfNeeded` returns
/// cached data immediately if it was fetched within that window.
///
/// All error paths — auth denial, network failure, missing coordinates,
/// missing forecast window — are handled gracefully. No errors are surfaced
/// to the caller; `fetchIfNeeded` always returns `nil` or a valid snapshot.
public struct WeatherService: Sendable {

    private static let logger = Logger(subsystem: "com.shift.weather", category: "WeatherService")

    public init() {}

    // MARK: - Public API

    /// Cache-first fetch of weather data for an event.
    ///
    /// - If `event.latitude == 0 && event.longitude == 0`: returns `nil` immediately.
    /// - If `event.weatherSnapshot` decodes to a fresh snapshot (< 30 min old): returns it without a network call.
    /// - Otherwise: fetches from WeatherKit, encodes the result to `event.weatherSnapshot`, and returns the new snapshot.
    /// - On any error (auth denied, network, parse): logs the error and returns the cached snapshot (decoded) or `nil`.
    ///
    /// - Important: The caller is responsible for saving the `ModelContext`
    ///   after this method returns — the service only mutates the model property.
    @MainActor
    public func fetchIfNeeded(for event: EventModel) async -> WeatherSnapshot? {
        // Guard: no coordinates — nothing to fetch
        guard event.latitude != 0 || event.longitude != 0 else {
            return nil
        }

        // Attempt to decode any existing cached snapshot
        let cachedSnapshot = decodedSnapshot(from: event.weatherSnapshot)

        // Cache hit — return immediately without a network call
        if let cachedSnapshot, cachedSnapshot.isFresh {
            return cachedSnapshot
        }

        // Collect block identity + schedule as plain value types before leaving @MainActor
        let blockTokens: [(id: UUID, scheduledStart: Date)] = (event.tracks ?? [])
            .flatMap { $0.blocks ?? [] }
            .sorted { $0.scheduledStart < $1.scheduledStart }
            .map { (id: $0.id, scheduledStart: $0.scheduledStart) }

        let latitude = event.latitude
        let longitude = event.longitude
        let date = event.date

        // Fetch fresh data from WeatherKit
        do {
            let snapshot = try await fetch(
                latitude: latitude,
                longitude: longitude,
                date: date,
                blockTokens: blockTokens
            )
            // Write back to model — caller saves context
            event.weatherSnapshot = try? JSONEncoder().encode(snapshot)
            return snapshot
        } catch {
            Self.logger.error("WeatherKit fetch failed: \(error.localizedDescription) — falling back to cached data")
            // Return stale cache rather than nil when available
            return cachedSnapshot
        }
    }

    // MARK: - Internal Fetch

    /// Fetches WeatherKit hourly data and resolves per-block rain probabilities.
    ///
    /// Each block's `scheduledStart` is matched to the nearest `HourWeather` entry
    /// within 3600 seconds. Blocks with no matching entry are omitted from the result.
    ///
    /// - Parameter blockTokens: Lightweight value-type snapshots of each block's
    ///   identity and schedule, extracted on `@MainActor` before this call.
    /// - Throws: `WeatherError` (including `.permissionDenied`) or any underlying network error.
    public func fetch(
        latitude: Double,
        longitude: Double,
        date: Date,
        blockTokens: [(id: UUID, scheduledStart: Date)]
    ) async throws -> WeatherSnapshot {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let wk = WKWeatherService()
        let forecast = try await wk.weather(for: location, including: .hourly)

        let entries: [BlockRainEntry] = blockTokens.compactMap { token in
            guard let match = forecast.forecast.min(by: {
                abs($0.date.timeIntervalSince(token.scheduledStart)) <
                    abs($1.date.timeIntervalSince(token.scheduledStart))
            }) else { return nil }

            // Only associate if the nearest entry is within a 1-hour window
            guard abs(match.date.timeIntervalSince(token.scheduledStart)) < 3600 else {
                return nil
            }

            return BlockRainEntry(
                blockId: token.id,
                rainProbability: match.precipitationChance
            )
        }

        return WeatherSnapshot(entries: entries, fetchedAt: Date())
    }

    // MARK: - Helpers

    private func decodedSnapshot(from data: Data?) -> WeatherSnapshot? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(WeatherSnapshot.self, from: data)
    }
}
