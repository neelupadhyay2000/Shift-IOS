import Foundation
import Testing
@testable import shiftTimeline

/// Guards the Guideline 1.2 Terms-acceptance contract (E24 Task 3): the version
/// string the client sends must be stable and non-empty (the RPC rejects blanks),
/// and the agreement copy must actually state the no-tolerance policy Apple
/// requires vendors to accept before publishing UGC.
@Suite("Marketplace terms acceptance")
struct MarketplaceTermsTests {

    @Test("current version is non-empty and stable")
    func versionIsUsable() {
        let version = MarketplaceTerms.currentVersion
        #expect(!version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        // The RPC raises 22023 on a blank version — a whitespace-only constant
        // would break every vendor opt-in at runtime.
        #expect(version == "2026-07-09")
    }

    @Test("agreement text states the no-tolerance policy and the response window")
    func agreementCoversGuideline12() {
        let text = MarketplaceTerms.agreementText.lowercased()
        #expect(text.contains("no-tolerance"))
        #expect(text.contains("objectionable"))
        #expect(text.contains("terms of service"))
        // Apple looks for a stated action commitment on reports.
        #expect(text.contains("24 hours"))
    }

    @Test("abuse contact is published for the moderation requirement")
    func moderationContactPublished() {
        #expect(ContentSafety.abuseEmail == "abuse@shifttimeline.app")
        #expect(ContentSafety.abuseEmail.contains("@"))
    }

    @Test("every reportable content type has a stable wire value")
    func reportableTypesMatchDatabaseCheck() {
        // Must match the content_reports.content_type CHECK constraint exactly.
        let expected: Set<String> = [
            "vendor_profile", "portfolio_item", "review", "message", "community_template",
        ]
        let actual = Set(ReportableContentType.allCases.map(\.rawValue))
        #expect(actual == expected)
    }
}
