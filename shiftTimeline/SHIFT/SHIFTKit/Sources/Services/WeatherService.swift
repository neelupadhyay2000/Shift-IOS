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

    // MARK: - Attribution (WeatherKit / App Review Guideline 5.2.5)

    /// The Apple Weather™ marks and legal-attribution link required wherever
    /// WeatherKit-derived data is displayed. Value type so it can cross actor
    /// boundaries into SwiftUI freely.
    public struct Attribution: Sendable, Equatable {
        /// Apple Weather combined mark for light backgrounds.
        public let markLightURL: URL
        /// Apple Weather combined mark for dark backgrounds.
        public let markDarkURL: URL
        /// Apple's legal attribution / data-sources page.
        public let legalPageURL: URL
    }

    /// Fetches the Apple Weather attribution (logo marks + legal link). Returns
    /// `nil` on failure so callers can omit the view rather than crash; the marks
    /// are stable, so a successful result can be cached by the caller.
    public func attribution() async -> Attribution? {
        do {
            let info = try await WKWeatherService.shared.attribution
            return Attribution(
                markLightURL: info.combinedMarkLightURL,
                markDarkURL: info.combinedMarkDarkURL,
                legalPageURL: info.legalPageURL
            )
        } catch {
            Self.logger.error("WeatherKit attribution fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Public API

    /// Cache-first fetch of weather data for an event.
    ///
    /// - If neither the event nor any block has coordinates: returns `nil` immediately.
    /// - If `event.weatherSnapshot` decodes to a fresh snapshot (< 30 min old): returns it without a network call.
    /// - Otherwise: fetches from WeatherKit, encodes the result to `event.weatherSnapshot`, and returns the new snapshot.
    /// - On any error (auth denied, network, parse): logs the error and returns the cached snapshot (decoded) or `nil`.
    ///
    /// - Important: The caller is responsible for saving the `ModelContext`
    ///   after this method returns — the service only mutates the model property.
    @MainActor
    public func fetchIfNeeded(for event: EventModel) async -> WeatherSnapshot? {
        // Guard: no coordinates at event level AND no blocks have their own venue coordinates.
        let allBlocks = (event.tracks ?? []).flatMap { $0.blocks ?? [] }
        let hasEventCoords = event.latitude != 0 || event.longitude != 0
        let hasAnyBlockCoords = allBlocks.contains { $0.blockLatitude != 0 || $0.blockLongitude != 0 }
        guard hasEventCoords || hasAnyBlockCoords else {
            return nil
        }

        // Attempt to decode any existing cached snapshot
        let cachedSnapshot = decodedSnapshot(from: event.weatherSnapshot)

        // Cache hit — return immediately without a network call
        if let cachedSnapshot, cachedSnapshot.isFresh {
            return cachedSnapshot
        }

        // Collect block identity + schedule + per-block coordinates as plain value types
        // before leaving @MainActor. Blocks with no venue lat/lng fall back to the event location.
        let eventLatitude = event.latitude
        let eventLongitude = event.longitude
        let blockTokens: [(id: UUID, scheduledStart: Date, latitude: Double, longitude: Double)] =
            (event.tracks ?? [])
                .flatMap { $0.blocks ?? [] }
                .sorted { $0.scheduledStart < $1.scheduledStart }
                .map { block in
                    let lat = block.blockLatitude != 0 ? block.blockLatitude : eventLatitude
                    let lng = block.blockLongitude != 0 ? block.blockLongitude : eventLongitude
                    return (id: block.id, scheduledStart: block.scheduledStart, latitude: lat, longitude: lng)
                }

        // Fetch fresh data from WeatherKit
        do {
            let snapshot = try await fetch(
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
    /// Blocks are grouped by their resolved location (rounded to 4 decimal places
    /// ≈11 m) so nearby blocks share a single WeatherKit request. Each block's
    /// `scheduledStart` is then matched to the nearest `HourWeather` entry within
    /// a 1-hour window. Blocks with no matching entry are omitted.
    ///
    /// - Parameter blockTokens: Value-type snapshots of each block including the
    ///   resolved coordinates, extracted on `@MainActor` before this call.
    /// - Throws: Any underlying WeatherKit or network error.
    public func fetch(
        blockTokens: [(id: UUID, scheduledStart: Date, latitude: Double, longitude: Double)]
    ) async throws -> WeatherSnapshot {
        // Round coordinates to 4dp to group blocks at the same venue into one request
        typealias CoordKey = String
        func key(_ lat: Double, _ lng: Double) -> CoordKey {
            String(format: "%.4f,%.4f", lat, lng)
        }

        // Build a mapping: coordKey -> [blockToken]
        var groups: [CoordKey: [(id: UUID, scheduledStart: Date)]] = [:]
        var coordForKey: [CoordKey: (Double, Double)] = [:]
        for token in blockTokens {
            let k = key(token.latitude, token.longitude)
            groups[k, default: []].append((id: token.id, scheduledStart: token.scheduledStart))
            coordForKey[k] = (token.latitude, token.longitude)
        }

        let wk = WKWeatherService()

        // Fetch each unique coordinate's hourly forecast concurrently. WeatherKit's
        // rate limiter is per-request, not per-connection, so issuing these in
        // parallel is the supported pattern and dramatically reduces latency for
        // multi-venue events (weddings with ceremony/reception at separate sites).
        let allEntries: [BlockRainEntry] = try await withThrowingTaskGroup(
            of: [BlockRainEntry].self
        ) { group in
            let now = Date()
            // WeatherKit's hourly forecast horizon (~10 days). Events further out
            // have no forecast available.
            let forecastHorizon = now.addingTimeInterval(10 * 24 * 3600)

            for (k, tokens) in groups {
                guard let (lat, lng) = coordForKey[k], lat != 0 || lng != 0 else { continue }
                group.addTask {
                    let location = CLLocation(latitude: lat, longitude: lng)

                    // The default `.hourly` query only covers ~the next day, so
                    // blocks further out return no match ("out of range"). Request
                    // the hourly window that actually spans these blocks instead,
                    // clamped to WeatherKit's forecast horizon.
                    let starts = tokens.map(\.scheduledStart)
                    guard let earliest = starts.min(), let latest = starts.max(),
                          earliest < forecastHorizon else { return [] }
                    let rangeStart = max(earliest.addingTimeInterval(-3600), now)
                    let rangeEnd = min(latest.addingTimeInterval(3600), forecastHorizon)
                    guard rangeStart < rangeEnd else { return [] }

                    let forecast = try await wk.weather(
                        for: location,
                        including: .hourly(startDate: rangeStart, endDate: rangeEnd)
                    )

                    return tokens.compactMap { token in
                        guard let match = forecast.forecast.min(by: {
                            abs($0.date.timeIntervalSince(token.scheduledStart)) <
                                abs($1.date.timeIntervalSince(token.scheduledStart))
                        }) else { return nil }

                        guard abs(match.date.timeIntervalSince(token.scheduledStart)) < 3600 else {
                            return nil
                        }

                        return BlockRainEntry(
                            blockId: token.id,
                            rainProbability: match.precipitationChance
                        )
                    }
                }
            }

            var collected: [BlockRainEntry] = []
            for try await entries in group {
                collected.append(contentsOf: entries)
            }
            return collected
        }

        return WeatherSnapshot(entries: allEntries, fetchedAt: Date())
    }

    /// Legacy overload kept for test compatibility — delegates to the grouped fetch.
    public func fetch(
        latitude: Double,
        longitude: Double,
        date: Date,
        blockTokens: [(id: UUID, scheduledStart: Date)]
    ) async throws -> WeatherSnapshot {
        let enriched = blockTokens.map { (id: $0.id, scheduledStart: $0.scheduledStart, latitude: latitude, longitude: longitude) }
        return try await fetch(blockTokens: enriched)
    }

    // MARK: - Helpers

    private func decodedSnapshot(from data: Data?) -> WeatherSnapshot? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(WeatherSnapshot.self, from: data)
    }
}
