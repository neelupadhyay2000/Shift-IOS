import Foundation
@testable import shiftTimeline
import Testing

@Suite("ContentReportDTO / UserBlockDTO — coding")
struct ContentReportDTOTests {

    @Test("content report encodes columns in snake_case")
    func reportEncodesSnakeCaseKeys() throws {
        let reporterID = UUID()
        let contentID = UUID()
        let dto = ContentReportDTO(
            reporterID: reporterID,
            contentType: "vendor_profile",
            contentID: contentID,
            reason: "spam"
        )
        let json = try jsonObject(from: dto)
        #expect(json["reporter_id"] as? String == reporterID.uuidString)
        #expect(json["content_type"] as? String == "vendor_profile")
        #expect(json["content_id"] as? String == contentID.uuidString)
        #expect(json["reason"] as? String == "spam")
        // Server-managed columns are never sent.
        #expect(json["status"] == nil)
        #expect(json["created_at"] == nil)
        #expect(json["reporterID"] == nil)
    }

    @Test("content report round-trips")
    func reportRoundTrips() throws {
        let dto = ContentReportDTO(
            reporterID: UUID(),
            contentType: "portfolio_item",
            contentID: UUID(),
            reason: "misleading"
        )
        #expect(try roundTrip(dto) == dto)
    }

    @Test("user block encodes the pair in snake_case")
    func blockEncodesSnakeCaseKeys() throws {
        let blocker = UUID()
        let blocked = UUID()
        let dto = UserBlockDTO(blockerID: blocker, blockedID: blocked)
        let json = try jsonObject(from: dto)
        #expect(json["blocker_id"] as? String == blocker.uuidString)
        #expect(json["blocked_id"] as? String == blocked.uuidString)
        #expect(json["blockerID"] == nil)
    }

    @Test("reportable content types match the DB CHECK raw values")
    func contentTypeRawValues() {
        #expect(ReportableContentType.vendorProfile.rawValue == "vendor_profile")
        #expect(ReportableContentType.portfolioItem.rawValue == "portfolio_item")
        #expect(ReportableContentType.review.rawValue == "review")
        #expect(ReportableContentType.message.rawValue == "message")
    }
}
