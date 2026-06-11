import Foundation
import Models
import Testing
@testable import shiftTimeline

/// Covers how a user-entered custom vendor type rides the `event_vendors.role`
/// string column: outbound it replaces the `custom` raw value; inbound any
/// unrecognized role string becomes `.custom` with the string preserved as the
/// label. No server schema change needed.
@MainActor
struct VendorCustomRoleMappingTests {

    @Test func customLabelIsSentAsTheRoleString() {
        let vendor = VendorModel(name: "Lia", role: .custom, customRoleLabel: "Videographer")
        let dto = vendor.toDTO(eventID: UUID())
        #expect(dto.role == "Videographer")
    }

    @Test func builtInRoleSendsItsRawValue() {
        let vendor = VendorModel(name: "Marco", role: .dj, customRoleLabel: "")
        let dto = vendor.toDTO(eventID: UUID())
        #expect(dto.role == VendorRole.dj.rawValue)
    }

    @Test func customRoleWithoutLabelSendsCustomRawValue() {
        let vendor = VendorModel(name: "Sam", role: .custom)
        let dto = vendor.toDTO(eventID: UUID())
        #expect(dto.role == VendorRole.custom.rawValue)
    }

    @Test func unknownRoleStringAppliesAsCustomWithLabel() {
        let outbound = VendorModel(name: "Lia", role: .custom, customRoleLabel: "Videographer")
        let dto = outbound.toDTO(eventID: UUID())

        let inbound = VendorModel(name: "", role: .photographer)
        dto.apply(to: inbound)

        #expect(inbound.role == .custom)
        #expect(inbound.customRoleLabel == "Videographer")
    }

    @Test func knownRoleStringAppliesWithoutLabel() {
        let outbound = VendorModel(name: "Marco", role: .dj)
        let dto = outbound.toDTO(eventID: UUID())

        let inbound = VendorModel(name: "", role: .custom, customRoleLabel: "stale label")
        dto.apply(to: inbound)

        #expect(inbound.role == .dj)
        #expect(inbound.customRoleLabel.isEmpty)
    }
}
