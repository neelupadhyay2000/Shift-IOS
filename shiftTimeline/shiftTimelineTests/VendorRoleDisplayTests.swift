import Foundation
import Models
import Testing
@testable import shiftTimeline

/// Covers the role label shown for vendors: the user-entered custom type when
/// the role is `.custom`, otherwise the built-in role name.
@MainActor
struct VendorRoleDisplayTests {

    @Test func builtInRoleUsesItsDisplayName() {
        #expect(VendorRoleLabel.display(role: .dj, customLabel: "") == VendorRole.dj.displayName)
    }

    @Test func customRoleWithLabelUsesTheLabel() {
        #expect(VendorRoleLabel.display(role: .custom, customLabel: "Videographer") == "Videographer")
    }

    @Test func customRoleWithEmptyLabelFallsBackToCustom() {
        #expect(VendorRoleLabel.display(role: .custom, customLabel: "") == VendorRole.custom.displayName)
    }

    @Test func customRoleWithWhitespaceLabelFallsBackToCustom() {
        #expect(VendorRoleLabel.display(role: .custom, customLabel: "   ") == VendorRole.custom.displayName)
    }

    @Test func builtInRoleIgnoresStrayCustomLabel() {
        #expect(VendorRoleLabel.display(role: .florist, customLabel: "Videographer") == VendorRole.florist.displayName)
    }
}
