import Foundation
import Services
import Testing

/// `.serialized` ensures tests run sequentially within this suite so the
/// shared `MockURLProtocol` static state is never accessed concurrently.
@Suite(.serialized)
struct SunsetServiceTests {

    // MARK: - Mock URLProtocol

    private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var responseData: Data?
        nonisolated(unsafe) static var responseStatusCode: Int = 200
        nonisolated(unsafe) static var responseError: Error?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            if let error = Self.responseError {
                client?.urlProtocol(self, didFailWithError: error)
                return
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: Self.responseStatusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

            if let data = Self.responseData {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    /// Configures the mock and returns a ready-to-use `SunsetService`.
    /// Bundling setup here keeps individual tests free of static-state boilerplate.
    private func makeService(
        data: Data?,
        statusCode: Int = 200,
        error: Error? = nil
    ) -> SunsetService {
        MockURLProtocol.responseData = data
        MockURLProtocol.responseStatusCode = statusCode
        MockURLProtocol.responseError = error
<<<<<<< Updated upstream
        let config = URLSessionConfiguration.ephemeral
=======
        let config = URLSessionConfiguration.ephemeral		
>>>>>>> Stashed changes
        config.protocolClasses = [MockURLProtocol.self]
        return SunsetService(session: URLSession(configuration: config))
    }

    // MARK: - Successful Parse

    @Test func fetchReturnsSunsetAndGoldenHour() async throws {
        let json = """
        {
            "results": {
                "sunset": "2026-06-15T19:30:00+00:00",
                "civil_twilight_begin": "2026-06-15T18:45:00+00:00"
            },
            "status": "OK"
        }
        """
        let service = makeService(data: Data(json.utf8))
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15))!

        let result = try await service.fetch(latitude: 40.7128, longitude: -74.006, date: date)

        #expect(result.sunset != result.goldenHourStart)
    }

    // MARK: - API Error Status

    @Test func fetchThrowsOnNonOKStatus() async throws {
        let json = """
        {
            "results": {
                "sunset": "",
                "civil_twilight_begin": ""
            },
            "status": "INVALID_REQUEST"
        }
        """
        let service = makeService(data: Data(json.utf8))

        await #expect(throws: SunsetServiceError.self) {
            try await service.fetch(latitude: 0, longitude: 0, date: .now)
        }
    }

    // MARK: - HTTP Error

    @Test func fetchThrowsOnHTTPError() async throws {
        let service = makeService(data: Data(), statusCode: 500)

        await #expect(throws: SunsetServiceError.self) {
            try await service.fetch(latitude: 40.0, longitude: -74.0, date: .now)
        }
    }

    // MARK: - Malformed JSON

    @Test func fetchThrowsOnMalformedJSON() async throws {
        let service = makeService(data: Data("not json".utf8))

        await #expect(throws: Error.self) {
            try await service.fetch(latitude: 40.0, longitude: -74.0, date: .now)
        }
    }

    // MARK: - Unparseable Dates

    @Test func fetchThrowsOnUnparseableDates() async throws {
        let json = """
        {
            "results": {
                "sunset": "not-a-date",
                "civil_twilight_begin": "also-not-a-date"
            },
            "status": "OK"
        }
        """
        let service = makeService(data: Data(json.utf8))

        await #expect(throws: SunsetServiceError.self) {
            try await service.fetch(latitude: 40.0, longitude: -74.0, date: .now)
        }
    }
}
