import Foundation
import Models
@testable import shiftTimeline
import Testing

@Suite("SupabaseWaitlistService — upsert payload construction")
struct WaitlistServiceTests {

    let profileID = UUID()

    @Test("vendor signup maps the VendorRole category to its raw value")
    func vendorPayload() {
        let payload = SupabaseWaitlistService.payload(
            profileID: profileID,
            role: .vendor,
            category: .photographer,
            region: "Toronto, ON"
        )
        #expect(payload.profileID == profileID)
        #expect(payload.interestRole == "vendor")
        #expect(payload.category == "photographer")
        #expect(payload.region == "Toronto, ON")
    }

    @Test("planner signup never carries a category, even if one is passed")
    func plannerDropsCategory() {
        let payload = SupabaseWaitlistService.payload(
            profileID: profileID,
            role: .planner,
            category: .dj,
            region: ""
        )
        #expect(payload.interestRole == "planner")
        #expect(payload.category == nil)
    }

    @Test("both-sided signup keeps the vendor category")
    func bothKeepsCategory() {
        let payload = SupabaseWaitlistService.payload(
            profileID: profileID,
            role: .both,
            category: .florist,
            region: "Ottawa, ON"
        )
        #expect(payload.interestRole == "both")
        #expect(payload.category == "florist")
    }

    @Test("vendor signup without a chosen category stays nil")
    func vendorNilCategory() {
        let payload = SupabaseWaitlistService.payload(
            profileID: profileID,
            role: .vendor,
            category: nil,
            region: ""
        )
        #expect(payload.category == nil)
    }

    @Test("region is trimmed of whitespace and newlines")
    func trimsRegion() {
        let payload = SupabaseWaitlistService.payload(
            profileID: profileID,
            role: .vendor,
            category: .caterer,
            region: "  Toronto, ON \n"
        )
        #expect(payload.region == "Toronto, ON")
    }

    @Test("custom category with a label sends the label as the category string")
    func customCategoryWithLabel() {
        let payload = SupabaseWaitlistService.payload(
            profileID: profileID,
            role: .vendor,
            category: .custom,
            customCategoryLabel: "  Videographer \n",
            region: ""
        )
        #expect(payload.category == "Videographer")
    }

    @Test("custom category without a label falls back to the custom raw value")
    func customCategoryWithoutLabel() {
        let payload = SupabaseWaitlistService.payload(
            profileID: profileID,
            role: .vendor,
            category: .custom,
            customCategoryLabel: "   ",
            region: ""
        )
        #expect(payload.category == VendorRole.custom.rawValue)
    }

    @Test("built-in category ignores a stray custom label")
    func builtInCategoryIgnoresLabel() {
        let payload = SupabaseWaitlistService.payload(
            profileID: profileID,
            role: .both,
            category: .dj,
            customCategoryLabel: "Videographer",
            region: ""
        )
        #expect(payload.category == VendorRole.dj.rawValue)
    }

    @Test("planner signup drops the custom label along with the category")
    func plannerDropsCustomLabel() {
        let payload = SupabaseWaitlistService.payload(
            profileID: profileID,
            role: .planner,
            category: .custom,
            customCategoryLabel: "Videographer",
            region: ""
        )
        #expect(payload.category == nil)
    }

    @Test("interest role raw values match the DB check constraint")
    func rawValuesMatchCheckConstraint() {
        #expect(WaitlistInterestRole.vendor.rawValue == "vendor")
        #expect(WaitlistInterestRole.planner.rawValue == "planner")
        #expect(WaitlistInterestRole.both.rawValue == "both")
        #expect(WaitlistInterestRole.allCases.count == 3)
    }

    @Test("every VendorRole raw value survives the category mapping", arguments: VendorRole.allCases)
    func categoryMapping(vendorRole: VendorRole) {
        let payload = SupabaseWaitlistService.payload(
            profileID: profileID,
            role: .vendor,
            category: vendorRole,
            region: ""
        )
        #expect(payload.category == vendorRole.rawValue)
        #expect(VendorRole(rawValue: payload.category ?? "") == vendorRole)
    }
}
