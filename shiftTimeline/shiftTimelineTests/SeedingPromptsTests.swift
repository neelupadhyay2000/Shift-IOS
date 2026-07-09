import Foundation
import Models
import Testing
@testable import shiftTimeline

/// Locks the eligibility + persistence logic behind the two cold-start seeding
/// prompts (E24 Task 2): the post-event "invite your vendors" card and the
/// one-time vendor opt-in sheet.
@Suite("Cold-start seeding prompts")
struct SeedingPromptsTests {

    // MARK: - Post-event invite prompt

    @Test("unclaimed = vendors with no linked profile")
    @MainActor
    func unclaimedFiltersByProfileID() {
        let claimed = VendorModel(name: "Ava", role: .photographer)
        claimed.profileId = UUID()
        let unclaimed = VendorModel(name: "Ben", role: .caterer)

        let result = PostEventInvitePrompt.unclaimedVendors([claimed, unclaimed])
        #expect(result.count == 1)
        #expect(result.first?.name == "Ben")
    }

    @Test("prompt requires completed + owner + ≥1 unclaimed + not dismissed")
    func eligibilityTruthTable() {
        // The one eligible combination.
        #expect(PostEventInvitePrompt.isEligible(
            isCompleted: true, isOwner: true, unclaimedCount: 1, isDismissed: false
        ))
        // Each gate individually blocks.
        #expect(!PostEventInvitePrompt.isEligible(
            isCompleted: false, isOwner: true, unclaimedCount: 1, isDismissed: false
        ))
        #expect(!PostEventInvitePrompt.isEligible(
            isCompleted: true, isOwner: false, unclaimedCount: 1, isDismissed: false
        ))
        #expect(!PostEventInvitePrompt.isEligible(
            isCompleted: true, isOwner: true, unclaimedCount: 0, isDismissed: false
        ))
        #expect(!PostEventInvitePrompt.isEligible(
            isCompleted: true, isOwner: true, unclaimedCount: 1, isDismissed: true
        ))
    }

    @Test("headline personalizes a single unclaimed vendor by role")
    @MainActor
    func headlinePersonalization() {
        let photographer = VendorModel(name: "Ava", role: .photographer)
        let caterer = VendorModel(name: "Ben", role: .caterer)

        let single = PostEventInvitePrompt.headline(for: [photographer])
        #expect(single.contains("photographer"))

        let plural = PostEventInvitePrompt.headline(for: [photographer, caterer])
        #expect(plural.contains("vendors"))
    }

    @Test("dismissal store round-trips per event and is idempotent")
    func dismissalStore() throws {
        let suiteName = "SeedingPromptsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PostEventInvitePromptStore(defaults: defaults)
        let eventA = UUID()
        let eventB = UUID()

        #expect(!store.isDismissed(eventID: eventA))

        store.dismiss(eventID: eventA)
        store.dismiss(eventID: eventA)   // idempotent — no duplicate entries
        #expect(store.isDismissed(eventID: eventA))
        #expect(!store.isDismissed(eventID: eventB))
        #expect(defaults.stringArray(forKey: "postEventInvitePromptDismissed")?.count == 1)
    }

    // MARK: - Vendor opt-in prompt

    @Test("opt-in requires ≥1 worked event, no profile, planner account, never shown")
    func optInEligibilityTruthTable() {
        #expect(VendorOptInPrompt.isEligible(
            workedEventCount: 1, hasVendorProfile: false, isVendorAccount: false, alreadyShown: false
        ))
        #expect(VendorOptInPrompt.isEligible(
            workedEventCount: 12, hasVendorProfile: false, isVendorAccount: false, alreadyShown: false
        ))
        // Each gate individually blocks.
        #expect(!VendorOptInPrompt.isEligible(
            workedEventCount: 0, hasVendorProfile: false, isVendorAccount: false, alreadyShown: false
        ))
        #expect(!VendorOptInPrompt.isEligible(
            workedEventCount: 3, hasVendorProfile: true, isVendorAccount: false, alreadyShown: false
        ))
        #expect(!VendorOptInPrompt.isEligible(
            workedEventCount: 3, hasVendorProfile: false, isVendorAccount: true, alreadyShown: false
        ))
        #expect(!VendorOptInPrompt.isEligible(
            workedEventCount: 3, hasVendorProfile: false, isVendorAccount: false, alreadyShown: true
        ))
    }

    @Test("opt-in headline is singular-safe")
    func optInHeadline() {
        #expect(VendorOptInPrompt.headline(workedEventCount: 1).contains("1 event"))
        #expect(!VendorOptInPrompt.headline(workedEventCount: 1).contains("events"))
        #expect(VendorOptInPrompt.headline(workedEventCount: 4).contains("4 events"))
    }
}
