import Foundation
import Models
import Services
import Supabase
@testable import shiftTimeline
import SwiftData
import Testing

/// The sync composition root. The single feature flag, when on,
/// builds `SupabaseSyncStack`, which routes every timeline write through the
/// Outbox provider (so writes sync) and shares one `RealtimeEchoSuppressor`
/// between the push path and the realtime applier (so a device's own writes
/// aren't re-applied as echoes). Network drains (`start()`) are not exercised
/// here — construction is inert and offline; the underlying flush/hydration
/// pieces have their own suites.
@Suite("Supabase sync stack (cutover)")
@MainActor
struct SupabaseSyncStackTests {

    private struct Stack {
        let container: ModelContainer
        let context: ModelContext
        let stack: SupabaseSyncStack
    }

    private func makeClient() throws -> SupabaseClient {
        let url = try #require(URL(string: "https://example.supabase.co"))
        return SupabaseClientProvider(supabaseURL: url, supabaseKey: "test-anon-key").client
    }

    private func makeStack(owner: UUID? = UUID()) throws -> Stack {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        context.autosaveEnabled = false
        let stack = SupabaseSyncStack(
            client: try makeClient(),
            context: context,
            currentOwnerID: { owner }
        )
        return Stack(container: container, context: context, stack: stack)
    }

    @Test("writes through the stack's repository provider enqueue to the Outbox")
    func providerWritesEnqueueToOutbox() async throws {
        let owner = UUID()
        let s = try makeStack(owner: owner)

        let event = EventModel(title: "Cutover", date: fixedTimestamp, latitude: 0, longitude: 0)
        try await s.stack.repositoryProvider.events.insert(event)
        try s.context.save()

        let entries = try s.context.fetch(FetchDescriptor<OutboxEntry>())
        let entry = try #require(entries.first { $0.tableName == "events" && $0.rowID == event.id })
        #expect(entry.operation == "insert")

        // The enqueued payload is stamped with the current owner (the cutover's
        // owner resolver feeds the Outbox coordinator).
        let dto = try JSONDecoder().decode(EventDTO.self, from: try #require(entry.payload))
        #expect(dto.ownerID == owner)
    }

    @Test("a single echo suppressor backs both the write path and the realtime applier")
    func echoSuppressorIsShared() throws {
        let s = try makeStack()
        // The flusher records each sent write here; the realtime applier consults
        // the same instance — so a recorded write is recognized as a self-echo.
        let id = UUID()
        s.stack.echoSuppressor.recordLocalWrite(table: "events", id: id)
        #expect(s.stack.echoSuppressor.shouldSuppress(table: "events", id: id))
    }
}
