import Foundation
@testable import shiftTimeline
import Testing

@Suite("SupabaseContentReportService — report payload construction")
struct ContentReportServiceTests {

    let reporterID = UUID()
    let contentID = UUID()

    @Test("maps the content type and reason to their raw values")
    func mapsRawValues() {
        let payload = SupabaseContentReportService.reportPayload(
            reporterID: reporterID,
            contentType: .vendorProfile,
            contentID: contentID,
            reason: .harassment
        )
        #expect(payload.reporterID == reporterID)
        #expect(payload.contentType == "vendor_profile")
        #expect(payload.contentID == contentID)
        #expect(payload.reason == "harassment")
    }

    @Test("carries the content type for non-profile surfaces (reviews/messages)")
    func mapsOtherContentTypes() {
        let review = SupabaseContentReportService.reportPayload(
            reporterID: reporterID,
            contentType: .review,
            contentID: contentID,
            reason: .offensive
        )
        #expect(review.contentType == "review")
        #expect(review.reason == "offensive")

        let message = SupabaseContentReportService.reportPayload(
            reporterID: reporterID,
            contentType: .message,
            contentID: contentID,
            reason: .other
        )
        #expect(message.contentType == "message")
        #expect(message.reason == "other")
    }

    @Test("every report reason maps to a non-empty stored raw value")
    func allReasonsHaveRawValues() {
        for reason in ReportReason.allCases {
            let payload = SupabaseContentReportService.reportPayload(
                reporterID: reporterID,
                contentType: .vendorProfile,
                contentID: contentID,
                reason: reason
            )
            #expect(!payload.reason.isEmpty)
            #expect(payload.reason == reason.rawValue)
        }
    }
}
