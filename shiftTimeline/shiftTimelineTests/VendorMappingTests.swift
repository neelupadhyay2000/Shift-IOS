import Foundation
import Models
import Services
@testable import shiftTimeline
import SwiftData
import Testing

@Suite("VendorModel ↔ EventVendorDTO mapping")
@MainActor
struct VendorMappingTests {

    @Test("round-trip: scalars, contact→invite fields, threshold narrowing")
    func roundTrip() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let event = EventModel(title: "E", date: fixedTimestamp, latitude: 0, longitude: 0)
        let vendor = VendorModel(
            name: "Jane's Photo",
            role: .photographer,
            phone: "+14155550101",
            email: "jane@example.com",
            notificationThreshold: 600,
            hasAcknowledgedLatestShift: true
        )
        context.insert(event)
        context.insert(vendor)
        vendor.event = event
        vendor.pendingShiftDelta = 12
        vendor.invitedAt = fixedTimestamp

        let dto = try vendor.toDTO()
        #expect(dto.id == vendor.id)
        #expect(dto.eventID == event.id)
        #expect(dto.displayName == "Jane's Photo")
        #expect(dto.role == "photographer")
        #expect(dto.invitedPhone == "+14155550101")
        #expect(dto.invitedEmail == "jane@example.com")
        #expect(dto.notificationThreshold == 600)
        #expect(dto.hasAcknowledgedLatestShift == true)
        #expect(dto.pendingShiftDelta == 12)
        #expect(dto.invitedAt?.value == fixedTimestamp)
        // E14-only columns are not invented from the local model.
        #expect(dto.profileID == nil)
        #expect(dto.acceptedAt == nil)

        let model = dto.makeModel()
        #expect(model.id == vendor.id)
        #expect(model.name == "Jane's Photo")
        #expect(model.role == .photographer)
        #expect(model.phone == "+14155550101")
        #expect(model.email == "jane@example.com")
        #expect(model.notificationThreshold == 600)
        #expect(model.hasAcknowledgedLatestShift == true)
        #expect(model.pendingShiftDelta == 12)
        #expect(model.invitedAt == fixedTimestamp)
    }

    @Test("empty contact strings map to nil and back to empty")
    func emptyContactRoundTrip() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let event = EventModel(title: "E", date: fixedTimestamp, latitude: 0, longitude: 0)
        let vendor = VendorModel(name: "Contact-only", role: .custom)
        context.insert(event)
        context.insert(vendor)
        vendor.event = event

        let dto = try vendor.toDTO()
        #expect(dto.invitedPhone == nil)
        #expect(dto.invitedEmail == nil)

        let model = dto.makeModel()
        #expect(model.phone == "")
        #expect(model.email == "")
    }

    @Test("forward: throws when the vendor is detached from its event")
    func detachedThrows() throws {
        let vendor = VendorModel(name: "Orphan", role: .custom)
        #expect(throws: ModelMappingError.missingEvent) {
            _ = try vendor.toDTO()
        }
    }
}
