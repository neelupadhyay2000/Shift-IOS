import Foundation
@testable import shiftTimeline
import Testing

/// SHIFT-663 — proves the Realtime connection-budget math the cutover plans
/// against. The load-bearing assumption is **one connection per active device**
/// (enforced by `RealtimeLifecycleManager`, which keeps a single multiplexed
/// channel open only while foregrounded on an event); these tests pin that and
/// the headroom arithmetic for the plan tiers.
@Suite("Realtime connection budget (SHIFT-663)")
struct RealtimeConnectionBudgetTests {

    @Test("the tier presets account one connection per active device")
    func presetsAreOneConnectionPerDevice() {
        #expect(RealtimeConnectionBudget.free.connectionsPerActiveDevice == 1)
        #expect(RealtimeConnectionBudget.pro.connectionsPerActiveDevice == 1)
    }

    @Test("usable connections reserve the headroom under the tier ceiling")
    func usableConnectionsReserveHeadroom() {
        #expect(RealtimeConnectionBudget.free.usableConnections == 140) // 200 · 70%
        #expect(RealtimeConnectionBudget.pro.usableConnections == 350)  // 500 · 70%
    }

    @Test("max concurrent devices is the usable ceiling over per-device cost")
    func maxConcurrentDevices() {
        #expect(RealtimeConnectionBudget.free.maxConcurrentDevices == 140)
        #expect(RealtimeConnectionBudget.pro.maxConcurrentDevices == 350)
    }

    @Test("within-budget holds up to the usable ceiling and fails one past it")
    func withinBudgetBoundary() {
        let pro = RealtimeConnectionBudget.pro
        #expect(pro.isWithinBudget(expectedConcurrentDevices: 350))
        #expect(!pro.isWithinBudget(expectedConcurrentDevices: 351))
    }

    @Test("a heavier per-device connection cost shrinks the device budget")
    func multiConnectionPerDevice() {
        let budget = RealtimeConnectionBudget(
            tierCeiling: 200, connectionsPerActiveDevice: 2, headroomFraction: 0.3
        )
        #expect(budget.usableConnections == 140)
        #expect(budget.maxConcurrentDevices == 70)
        #expect(budget.isWithinBudget(expectedConcurrentDevices: 70))
        #expect(!budget.isWithinBudget(expectedConcurrentDevices: 71))
    }

    @Test("zero headroom uses the whole ceiling; full headroom uses none")
    func headroomBounds() {
        let none = RealtimeConnectionBudget(tierCeiling: 500, connectionsPerActiveDevice: 1, headroomFraction: 0)
        let all = RealtimeConnectionBudget(tierCeiling: 500, connectionsPerActiveDevice: 1, headroomFraction: 1)
        #expect(none.usableConnections == 500)
        #expect(all.usableConnections == 0)
    }

    @Test("a zero per-device cost can't be divided — no devices fit")
    func zeroPerDeviceGuard() {
        let budget = RealtimeConnectionBudget(
            tierCeiling: 200, connectionsPerActiveDevice: 0, headroomFraction: 0.3
        )
        #expect(budget.maxConcurrentDevices == 0)
    }
}
