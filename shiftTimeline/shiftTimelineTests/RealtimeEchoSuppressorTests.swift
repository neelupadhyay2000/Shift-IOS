import Foundation
@testable import shiftTimeline
import Testing

@Suite("RealtimeEchoSuppressor")
@MainActor
struct RealtimeEchoSuppressorTests {

    @Test("suppresses a recently-written row's echo within the window")
    func suppressesWithinWindow() {
        var now = Date(timeIntervalSince1970: 1_000)
        let suppressor = RealtimeEchoSuppressor(window: 10, clock: { now })
        let id = UUID()

        suppressor.recordLocalWrite(table: "events", id: id)
        now = now.addingTimeInterval(5) // within the 10s window

        #expect(suppressor.shouldSuppress(table: "events", id: id))
    }

    @Test("stops suppressing once the echo window lapses")
    func notSuppressedAfterWindow() {
        var now = Date(timeIntervalSince1970: 1_000)
        let suppressor = RealtimeEchoSuppressor(window: 10, clock: { now })
        let id = UUID()

        suppressor.recordLocalWrite(table: "events", id: id)
        now = now.addingTimeInterval(15) // past the window

        #expect(!suppressor.shouldSuppress(table: "events", id: id))
    }

    @Test("never suppresses a row this device did not write")
    func notSuppressedForUnknownRow() {
        let suppressor = RealtimeEchoSuppressor()
        #expect(!suppressor.shouldSuppress(table: "events", id: UUID()))
    }

    @Test("keys suppression by table and id")
    func keyedByTableAndID() {
        let suppressor = RealtimeEchoSuppressor()
        let id = UUID()
        suppressor.recordLocalWrite(table: "events", id: id)

        #expect(suppressor.shouldSuppress(table: "events", id: id))
        #expect(!suppressor.shouldSuppress(table: "blocks", id: id))
        #expect(!suppressor.shouldSuppress(table: "events", id: UUID()))
    }
}
