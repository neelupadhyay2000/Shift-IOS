import Foundation

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
