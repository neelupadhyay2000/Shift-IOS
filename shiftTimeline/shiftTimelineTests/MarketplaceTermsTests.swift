import Foundation
import Testing
@testable import shiftTimeline

/// Guards the Guideline 1.2 Terms-acceptance contract (E24 Task 3): the version
/// string the client sends must be stable and non-empty (the RPC rejects blanks),
/// and the agreement copy must actually state the no-tolerance policy Apple
/// requires vendors to accept before publishing UGC.
@Suite("Marketplace terms acceptance")
struct MarketplaceTermsTests {

    /// The old version of this test hard-coded the literal date, which made it a
    /// changelog: every Terms revision failed it, and the fix was always to retype
    /// the constant — proving nothing. What matters is the shape the RPC requires:
    /// a non-blank version (it raises 22023 on blanks) that sorts chronologically,
    /// so a later revision can re-prompt only users whose recorded version is stale.
    @Test("current version is a non-blank, sortable ISO date")
    func versionIsUsable() {
        let version = MarketplaceTerms.currentVersion
        #expect(!version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(version.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil)
    }

    /// The version recorded as accepted must name the same day as the Effective
    /// Date on the hosted Terms, or a vendor's stored consent points at a document
    /// that didn't say what they agreed to. Change both together, or not at all.
    @Test("the recorded version matches the hosted Terms' Effective Date")
    func versionMatchesHostedTerms() {
        #expect(MarketplaceTerms.currentVersion == "2026-07-10")
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

    /// The vendor opt-in screen is where consent to disclose business contact is
    /// given, so the agreement copy has to say so — not just the hosted Terms.
    @Test("agreement text discloses that accepted planners see the vendor's contact")
    func agreementDisclosesContactSharing() {
        let text = MarketplaceTerms.agreementText.lowercased()
        #expect(text.contains("business email"))
        #expect(text.contains("accept"))
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
