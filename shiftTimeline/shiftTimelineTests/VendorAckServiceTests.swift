import Foundation
import Models
import Testing
@testable import shiftTimeline

/// In-process fake `VendorAckWriting` — records the targeted writes.
/// @MainActor + final gives implicit Sendable (mirrors the other fakes).
@MainActor
final class FakeVendorAckWriter: VendorAckWriting {
    private(set) var calls: [(id: UUID, value: Bool)] = []
    var shouldThrow = false

    func setAcknowledged(eventVendorID: UUID, to value: Bool) async throws {
        if shouldThrow { throw URLError(.badServerResponse) }
        calls.append((eventVendorID, value))
    }
}

@Suite("Vendor ack write (SHIFT-632)")
@MainActor
struct VendorAckServiceTests {

    private func vendor() -> VendorModel {
        let vendor = VendorModel(name: "Avery", role: .photographer)
        vendor.hasAcknowledgedLatestShift = false
        vendor.pendingShiftDelta = 300
        return vendor
    }

    @Test func applyLocalAckSetsFlagAndClearsPending() {
        let service = VendorAckService(writer: FakeVendorAckWriter())
        let vendor = vendor()

        service.applyLocalAck(vendor)

        #expect(vendor.hasAcknowledgedLatestShift == true)
        #expect(vendor.pendingShiftDelta == nil)
    }

    @Test func pushAckWritesOnlyAckColumnForThatRow() async throws {
        let writer = FakeVendorAckWriter()
        let service = VendorAckService(writer: writer)
        let vendor = vendor()

        try await service.pushAck(vendor)

        #expect(writer.calls.count == 1)
        #expect(writer.calls.first?.id == vendor.id)
        #expect(writer.calls.first?.value == true)
    }

    @Test func acknowledgeUpdatesLocallyThenRemotely() async throws {
        let writer = FakeVendorAckWriter()
        let service = VendorAckService(writer: writer)
        let vendor = vendor()

        try await service.acknowledge(vendor)

        #expect(vendor.hasAcknowledgedLatestShift == true)
        #expect(vendor.pendingShiftDelta == nil)
        #expect(writer.calls.map(\.id) == [vendor.id])
        #expect(writer.calls.first?.value == true)
    }

    /// The optimistic local update lands even if the remote write fails, so the
    /// banner dismisses; the planner just learns of the ack on a later sync.
    @Test func localAckSurvivesRemoteFailure() async {
        let writer = FakeVendorAckWriter()
        writer.shouldThrow = true
        let service = VendorAckService(writer: writer)
        let vendor = vendor()

        await #expect(throws: URLError.self) {
            try await service.acknowledge(vendor)
        }
        #expect(vendor.hasAcknowledgedLatestShift == true)
        #expect(vendor.pendingShiftDelta == nil)
    }
}
