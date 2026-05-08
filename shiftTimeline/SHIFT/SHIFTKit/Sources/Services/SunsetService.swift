import Foundation
import Models

/// Fetches sunset and golden hour times from sunrise-sunset.org. No API key required.
public struct SunsetService: Sendable {

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetches sunset and golden hour start for the given coordinates and date.
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

        guard let sunset = try? Date(decoded.results.sunset, strategy: Self.iso8601Strategy) else {
            throw SunsetServiceError.parseFailed
        }

        // Golden hour = 1 hour before sunset.
        let goldenHourStart = sunset.addingTimeInterval(-3600)

        return SunsetResult(sunset: sunset, goldenHourStart: goldenHourStart)
    }

    /// Cache-first fetch. Returns cached value if populated, fetches and writes back otherwise.
    /// Returns `nil` offline or if no coordinates exist. Caller must save the `ModelContext`.
    @MainActor
    public func fetchIfNeeded(for event: EventModel) async -> SunsetResult? {
        // Cache hit — no network call.
        if let sunset = event.sunsetTime,
           let goldenHour = event.goldenHourStart {
            return SunsetResult(sunset: sunset, goldenHourStart: goldenHour)
        }

        // No coordinates — can't query. Require both to avoid partial/invalid lookups.
        guard event.latitude != 0 && event.longitude != 0 else { return nil }

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

    /// Uses device local timezone, not UTC, so the API receives the correct calendar date.
    private static let localDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        // timeZone not set — inherits `TimeZone.current`.
        return f
    }()

    private static func dateString(from date: Date) -> String {
        localDateFormatter.string(from: date)
    }

    private static let iso8601Strategy: Date.ISO8601FormatStyle = .iso8601.dateTimeSeparator(.standard)
}

// MARK: - Result

/// Sunset and golden hour times.
public struct SunsetResult: Sendable, Equatable {
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
    }
}
