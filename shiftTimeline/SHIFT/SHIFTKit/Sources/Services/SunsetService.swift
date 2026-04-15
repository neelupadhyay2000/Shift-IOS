import Foundation
import Models

/// Fetches sunset and golden hour (civil twilight) times from the
/// sunrise-sunset.org public API for a given coordinate and date.
///
/// No API key required. Callers are responsible for caching the result
/// to avoid redundant network calls.
public struct SunsetService: Sendable {

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetches sunset and civil twilight begin (golden hour proxy) for
    /// the given coordinates and date.
    ///
    /// - Returns: A ``SunsetResult`` with sunset and golden hour start times
    ///   in the local calendar, or throws on network/parse failure.
    public func fetch(
        latitude: Double,
        longitude: Double,
        date: Date
    ) async throws -> SunsetResult {
        let dateString = Self.dateString(from: date)

        var components = URLComponents(string: "https://api.sunrise-sunset.org/json")
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lng", value: String(longitude)),
            URLQueryItem(name: "date", value: dateString),
            URLQueryItem(name: "formatted", value: "0"),
        ]

        guard let url = components?.url else {
            throw SunsetServiceError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode) else {
            throw SunsetServiceError.networkError
        }

        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)

        guard decoded.status == "OK" else {
            throw SunsetServiceError.apiError(decoded.status)
        }

        guard let sunset = try? Date(decoded.results.sunset, strategy: Self.iso8601Strategy),
              let civilTwilightBegin = try? Date(decoded.results.civil_twilight_begin, strategy: Self.iso8601Strategy) else {
            throw SunsetServiceError.parseFailed
        }

        return SunsetResult(sunset: sunset, goldenHourStart: civilTwilightBegin)
    }

    /// Checks the event's cached sunset data first. If already populated,
    /// returns it immediately without a network call. Otherwise fetches from
    /// the API and writes the result back to the event model.
    ///
    /// When the device is offline and no cached data exists, returns `nil`
    /// so callers can show "Unknown" instead of crashing.
    ///
    /// - Important: The caller is responsible for saving the `ModelContext`
    ///   after this method returns — the service only mutates the model.
    @MainActor
    public func fetchIfNeeded(for event: EventModel) async -> SunsetResult? {
        // Cache hit — no network call.
        if let sunset = event.sunsetTime,
           let goldenHour = event.goldenHourStart {
            return SunsetResult(sunset: sunset, goldenHourStart: goldenHour)
        }

        // No coordinates — can't query.
        guard event.latitude != 0 || event.longitude != 0 else { return nil }

        do {
            let result = try await fetch(
                latitude: event.latitude,
                longitude: event.longitude,
                date: event.date
            )
            event.sunsetTime = result.sunset
            event.goldenHourStart = result.goldenHourStart
            return result
        } catch {
            // Offline or API failure — graceful nil.
            return nil
        }
    }

    // MARK: - Formatters

    private static func dateString(from date: Date) -> String {
        date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
    }

    private static let iso8601Strategy: Date.ISO8601FormatStyle = .iso8601.dateTimeSeparator(.standard)
}

// MARK: - Result

/// Sunset and golden hour times returned by ``SunsetService``.
public struct SunsetResult: Sendable, Equatable {
    /// The exact sunset time (UTC, convert to local for display).
    public let sunset: Date

    /// Civil twilight begin — a good proxy for golden hour start.
    public let goldenHourStart: Date

    public init(sunset: Date, goldenHourStart: Date) {
        self.sunset = sunset
        self.goldenHourStart = goldenHourStart
    }
}

// MARK: - Errors

public enum SunsetServiceError: Error, Sendable, LocalizedError {
    case invalidURL
    case networkError
    case apiError(String)
    case parseFailed

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Failed to build sunset API URL."
        case .networkError: return "Network request to sunset API failed."
        case .apiError(let status): return "Sunset API returned status: \(status)"
        case .parseFailed: return "Failed to parse sunset times from API response."
        }
    }
}

// MARK: - API Response DTO

private struct APIResponse: Decodable {
    let results: Results
    let status: String

    struct Results: Decodable {
        let sunset: String
        let civil_twilight_begin: String
    }
}
