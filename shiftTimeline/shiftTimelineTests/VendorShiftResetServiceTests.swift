import Foundation
import Models
import Services
import SwiftData
import Testing
@testable import shiftTimeline

/// In-process fake `VendorShiftResetWriting` — records the resets pushed.
/// @MainActor + final gives implicit Sendable (mirrors the other fakes).
@MainActor
final class FakeVendorShiftResetWriter: VendorShiftResetWriting {
    private(set) var calls: [(id: UUID, delta: Double)] = []

    func resetAcknowledgment(eventVendorID: UUID, pendingShiftDelta: Double) async throws {
        calls.append((eventVendorID, pendingShiftDelta))
    }
}

@Suite("Vendor shift reset push (SHIFT-634)")
@MainActor
struct VendorShiftResetServiceTests {

    private func makeEvent(in context: ModelContext, vendorDeltas: [Double?]) -> (EventModel, [VendorModel]) {
        let event = EventModel(title: "E", date: .now, latitude: 0, longitude: 0)
        context.insert(event)
        let vendors = vendorDeltas.map { delta -> VendorModel in
            let vendor = VendorModel(name: "V", role: .photographer)
            vendor.event = event
            vendor.hasAcknowledgedLatestShift = true
            vendor.pendingShiftDelta = delta
            context.insert(vendor)
            return vendor
        }
        return (event, vendors)
    }

    @Test("snapshot includes only vendors with a pending shift delta")
    func resetsSnapshotIncludesPendingOnly() throws {
        let container = try PersistenceController.forTesting()
        let (event, vendors) = makeEvent(in: container.mainContext, vendorDeltas: [900, nil, 300])

        let resets = VendorShiftResetService.resets(for: event)

        #expect(resets.count == 2)
        #expect(Set(resets.map(\.eventVendorID)) == Set([vendors[0].id, vendors[2].id]))
        #expect(resets.first { $0.eventVendorID == vendors[0].id }?.pendingShiftDelta == 900)
        #expect(resets.first { $0.eventVendorID == vendors[2].id }?.pendingShiftDelta == 300)
    }

    @Test("push writes a reset for every snapshotted vendor")
    func pushResetWritesEach() async throws {
        let writer = FakeVendorShiftResetWriter()
        let service = VendorShiftResetService(writer: writer)
        let a = UUID(), b = UUID()
        let resets = [
            VendorAckReset(eventVendorID: a, pendingShiftDelta: 900),
            VendorAckReset(eventVendorID: b, pendingShiftDelta: 300),
        ]

        await service.pushReset(resets)

        #expect(writer.calls.count == 2)
        #expect(Set(writer.calls.map(\.id)) == Set([a, b]))
        #expect(writer.calls.first { $0.id == a }?.delta == 900)
        #expect(writer.calls.first { $0.id == b }?.delta == 300)
    }

    @Test("empty snapshot pushes nothing")
    func pushResetEmptyIsNoOp() async {
        let writer = FakeVendorShiftResetWriter()
        await VendorShiftResetService(writer: writer).pushReset([])
        #expect(writer.calls.isEmpty)
    }
}
