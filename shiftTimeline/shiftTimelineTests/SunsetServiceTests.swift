import Foundation
import Services
import Testing

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

    private func makeService() -> (SunsetService, URLSession) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        return (SunsetService(session: session), session)
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
        MockURLProtocol.responseData = Data(json.utf8)
        MockURLProtocol.responseStatusCode = 200
        MockURLProtocol.responseError = nil

        let (service, _) = makeService()
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
        MockURLProtocol.responseData = Data(json.utf8)
        MockURLProtocol.responseStatusCode = 200
        MockURLProtocol.responseError = nil

        let (service, _) = makeService()

        await #expect(throws: SunsetServiceError.self) {
            try await service.fetch(latitude: 0, longitude: 0, date: .now)
        }
    }

    // MARK: - HTTP Error

    @Test func fetchThrowsOnHTTPError() async throws {
        MockURLProtocol.responseData = Data()
        MockURLProtocol.responseStatusCode = 500
        MockURLProtocol.responseError = nil

        let (service, _) = makeService()

        await #expect(throws: SunsetServiceError.self) {
            try await service.fetch(latitude: 40.0, longitude: -74.0, date: .now)
        }
    }

    // MARK: - Malformed JSON

    @Test func fetchThrowsOnMalformedJSON() async throws {
        MockURLProtocol.responseData = Data("not json".utf8)
        MockURLProtocol.responseStatusCode = 200
        MockURLProtocol.responseError = nil

        let (service, _) = makeService()

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
        MockURLProtocol.responseData = Data(json.utf8)
        MockURLProtocol.responseStatusCode = 200
        MockURLProtocol.responseError = nil

        let (service, _) = makeService()

        await #expect(throws: SunsetServiceError.self) {
            try await service.fetch(latitude: 40.0, longitude: -74.0, date: .now)
        }
    }
}
