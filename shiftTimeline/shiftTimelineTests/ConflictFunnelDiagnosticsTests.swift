import Foundation
import Models
import Services
@testable import shiftTimeline
import SwiftData
import Supabase
import Testing

/// SHIFT-668 — the `.conflict` funnel stage must light up when LWW actually
/// resolves a race (a strictly-older remote version is skipped). Routine
/// re-deliveries (equal version) and normal newer-wins applies stay silent so
/// the stage is a high-signal indicator, not noise. Closes the one funnel gap
/// found in the SHIFT-667 audit: conflict previously had zero emitters, so the
/// diagnostics row could never go green and telemetry never saw LWW activity.
@Suite("Conflict funnel diagnostics")
@MainActor
struct ConflictFunnelDiagnosticsTests {

    private let t1 = Date(timeIntervalSince1970: 1_780_000_000)
    private let t2 = Date(timeIntervalSince1970: 1_790_000_000)

    private struct Stack {
        let container: ModelContainer
        let applier: RealtimeChangeApplier
        let diagnostics: SyncDiagnosticsCenter
    }

    private func makeStack() throws -> Stack {
        let container = try PersistenceController.forTesting()
        let diagnostics = SyncDiagnosticsCenter(
            defaults: .standard,
            storageKey: "test.conflict.\(UUID().uuidString)",
            maxEvents: 50
        )
        return Stack(
            container: container,
            applier: RealtimeChangeApplier(context: container.mainContext, diagnostics: diagnostics),
            diagnostics: diagnostics
        )
    }

    private func eventChange(id: UUID, title: String, updatedAt: Date?, deletedAt: Date? = nil) throws -> RealtimeChange {
        let dto = EventDTO(
            id: id, ownerID: UUID(), title: title, date: PostgresTimestamp(t1),
            status: "planning", updatedAt: PostgresTimestamp(updatedAt), deletedAt: PostgresTimestamp(deletedAt)
        )
        return .upsert(table: "events", record: try JSONObject(dto))
    }

    private func conflictEvents(_ diagnostics: SyncDiagnosticsCenter) -> [DiagnosticEvent] {
        diagnostics.events.filter { $0.category == .conflict }
    }

    @Test("a stale remote version being skipped records a conflict-stage event")
    func staleSkipRecordsConflict() throws {
        let stack = try makeStack()
        let id = UUID()
        try stack.applier.apply(eventChange(id: id, title: "v2", updatedAt: t2)) // newer lands first
        try stack.applier.apply(eventChange(id: id, title: "v1", updatedAt: t1)) // stale arrives late

        let recorded = conflictEvents(stack.diagnostics)
        #expect(recorded.count == 1)
        #expect(recorded.first?.name == "staleVersionSkipped")
        #expect(recorded.first?.params["table"] == "events")
    }

    @Test("an equal-version re-delivery is silent (not a conflict)")
    func equalVersionSkipIsSilent() throws {
        let stack = try makeStack()
        let id = UUID()
        try stack.applier.apply(eventChange(id: id, title: "v1", updatedAt: t1))
        try stack.applier.apply(eventChange(id: id, title: "v1", updatedAt: t1)) // re-delivery

        #expect(conflictEvents(stack.diagnostics).isEmpty)
    }

    @Test("a normal newer-wins apply is silent")
    func newerApplyIsSilent() throws {
        let stack = try makeStack()
        let id = UUID()
        try stack.applier.apply(eventChange(id: id, title: "v1", updatedAt: t1))
        try stack.applier.apply(eventChange(id: id, title: "v2", updatedAt: t2))

        #expect(conflictEvents(stack.diagnostics).isEmpty)
    }

    @Test("a stale tombstone being skipped records a conflict-stage event")
    func staleTombstoneSkipRecordsConflict() throws {
        let stack = try makeStack()
        let id = UUID()
        try stack.applier.apply(eventChange(id: id, title: "edited", updatedAt: t2))           // newer edit
        try stack.applier.apply(eventChange(id: id, title: "x", updatedAt: t1, deletedAt: t1)) // older delete

        let recorded = conflictEvents(stack.diagnostics)
        #expect(recorded.count == 1)
        #expect(recorded.first?.name == "staleVersionSkipped")
    }
}
