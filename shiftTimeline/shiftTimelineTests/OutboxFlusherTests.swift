import Foundation
import Models
import Services
@testable import shiftTimeline
import SwiftData
import Testing

/// SHIFT-611: the Outbox flushes FIFO, deletes on success, halts at the first
/// failure with exponential backoff, and re-sends idempotently (no duplicate
/// rows). The real network sender hits Supabase, so the flusher is driven here
/// against a fake `OutboxSending` that models an idempotent upsert-by-id.
@Suite("Outbox flush")
@MainActor
struct OutboxFlusherTests {

    // MARK: - Fakes

    /// Records every send and models the server as a set of rows keyed by
    /// `table:id` — so an upsert collapses re-sends of the same row.
    @MainActor
    final class FakeSender: OutboxSending {
        private(set) var sent: [OutboxItem] = []
        private(set) var liveRows: Set<String> = []
        /// Fail the next N sends (then succeed).
        var failuresRemaining = 0
        /// Always fail sends targeting these tables.
        var failTables: Set<String> = []

        func send(_ item: OutboxItem) async throws {
            if failTables.contains(item.table) { throw FakeError.boom }
            if failuresRemaining > 0 {
                failuresRemaining -= 1
                throw FakeError.boom
            }
            sent.append(item)
            let key = "\(item.table):\(item.rowID.uuidString)"
            switch item.operation {
            case .insert, .update: liveRows.insert(key)
            case .delete: liveRows.remove(key)
            }
        }
    }

    enum FakeError: Error { case boom }

    /// Captures requested backoff delays without actually sleeping.
    actor SleepRecorder {
        private(set) var delays: [TimeInterval] = []
        func record(_ delay: TimeInterval) { delays.append(delay) }
    }

    // MARK: - Stack

    private struct Stack {
        let container: ModelContainer
        let context: ModelContext
        let sender: FakeSender
        let flusher: OutboxFlusher
    }

    private func makeStack(
        echoSuppressor: RealtimeEchoSuppressor? = nil,
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { _ in }
    ) throws -> Stack {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        context.autosaveEnabled = false
        let sender = FakeSender()
        let flusher = OutboxFlusher(
            context: context,
            remote: sender,
            echoSuppressor: echoSuppressor,
            baseDelay: 1,
            maxDelay: 60,
            sleep: sleep
        )
        return Stack(container: container, context: context, sender: sender, flusher: flusher)
    }

    @discardableResult
    private func enqueue(
        _ context: ModelContext,
        seq: Int,
        table: String,
        op: OutboxOperation,
        rowID: UUID = UUID(),
        payload: Data? = Data("{}".utf8)
    ) -> OutboxEntry {
        let entry = OutboxEntry(
            sequence: seq, tableName: table, rowID: rowID, operation: op.rawValue, payload: payload
        )
        context.insert(entry)
        return entry
    }

    private func outbox(_ context: ModelContext) throws -> [OutboxEntry] {
        try context.fetch(FetchDescriptor<OutboxEntry>(sortBy: [SortDescriptor(\.sequence)]))
    }

    // MARK: - FIFO drain

    @Test("flush sends entries in FIFO order and deletes each on success")
    func flushOnceDrainsFIFOAndDeletes() async throws {
        let stack = try makeStack()
        let r1 = UUID(), r2 = UUID(), r3 = UUID()
        enqueue(stack.context, seq: 1, table: "events", op: .insert, rowID: r1)
        enqueue(stack.context, seq: 2, table: "tracks", op: .insert, rowID: r2)
        enqueue(stack.context, seq: 3, table: "blocks", op: .insert, rowID: r3)
        try stack.context.save()

        let outcome = await stack.flusher.flushOnce()

        #expect(outcome == .drained)
        #expect(stack.sender.sent.map(\.rowID) == [r1, r2, r3])
        #expect(try outbox(stack.context).isEmpty)
    }

    // MARK: - Head-of-line halt + backoff

    @Test("a failed send halts the pass at the head and asks for a backoff retry")
    func flushOnceHaltsAtFirstFailure() async throws {
        let stack = try makeStack()
        let head = enqueue(stack.context, seq: 1, table: "events", op: .insert)
        enqueue(stack.context, seq: 2, table: "tracks", op: .insert)
        try stack.context.save()
        stack.sender.failuresRemaining = 1 // the head fails

        let outcome = await stack.flusher.flushOnce()

        #expect(outcome == .retry(after: 1)) // backoff(attempt 1, base 1)
        #expect(head.attempts == 1)
        #expect(stack.sender.sent.isEmpty)              // nothing got past the failed head
        #expect(try outbox(stack.context).count == 2)   // nothing deleted
    }

    @Test("successes before the failure are removed; the failed entry becomes the new head")
    func flushOnceDeletesSuccessesBeforeHalting() async throws {
        let stack = try makeStack()
        enqueue(stack.context, seq: 1, table: "events", op: .insert) // succeeds
        let failing = enqueue(stack.context, seq: 2, table: "tracks", op: .insert) // fails
        enqueue(stack.context, seq: 3, table: "blocks", op: .insert) // never reached
        try stack.context.save()
        stack.sender.failTables = ["tracks"]

        let outcome = await stack.flusher.flushOnce()

        #expect(outcome == .retry(after: 1))
        #expect(stack.sender.sent.map(\.table) == ["events"])
        #expect(failing.attempts == 1)
        let remaining = try outbox(stack.context)
        #expect(remaining.map(\.tableName) == ["tracks", "blocks"]) // events drained; head is now tracks
    }

    @Test("backoff grows with the entry's prior attempts")
    func flushOnceBackoffReflectsAttempts() async throws {
        let stack = try makeStack()
        let head = enqueue(stack.context, seq: 1, table: "events", op: .insert)
        head.attempts = 2 // two prior failures
        try stack.context.save()
        stack.sender.failTables = ["events"]

        let outcome = await stack.flusher.flushOnce()

        #expect(head.attempts == 3)
        #expect(outcome == .retry(after: 4)) // backoff(attempt 3, base 1) = 4
    }

    @Test("backoff is exponential and capped")
    func backoffIsExponentialAndCapped() {
        #expect(OutboxFlusher.backoffSeconds(forAttempt: 0, base: 1, cap: 60) == 0)
        #expect(OutboxFlusher.backoffSeconds(forAttempt: 1, base: 1, cap: 60) == 1)
        #expect(OutboxFlusher.backoffSeconds(forAttempt: 2, base: 1, cap: 60) == 2)
        #expect(OutboxFlusher.backoffSeconds(forAttempt: 3, base: 1, cap: 60) == 4)
        #expect(OutboxFlusher.backoffSeconds(forAttempt: 4, base: 1, cap: 60) == 8)
        #expect(OutboxFlusher.backoffSeconds(forAttempt: 7, base: 1, cap: 60) == 60) // 64 capped
        #expect(OutboxFlusher.backoffSeconds(forAttempt: 3, base: 2, cap: 60) == 8)
    }

    // MARK: - Idempotency

    @Test("re-sending the same row (insert + update) does not duplicate it")
    func reSendsDoNotDuplicateRows() async throws {
        let stack = try makeStack()
        let rid = UUID()
        // The accepted insert+update duplicate the enqueue layer can produce.
        enqueue(stack.context, seq: 1, table: "events", op: .insert, rowID: rid)
        enqueue(stack.context, seq: 2, table: "events", op: .update, rowID: rid)
        try stack.context.save()

        await stack.flusher.flushOnce()

        #expect(stack.sender.sent.count == 2)                              // both entries sent…
        #expect(stack.sender.liveRows == ["events:\(rid.uuidString)"])    // …but one logical row
        #expect(try outbox(stack.context).isEmpty)
    }

    // MARK: - Deletes & echo suppression

    @Test("a successful send records the write for realtime echo suppression")
    func successRecordsEchoSuppression() async throws {
        let suppressor = RealtimeEchoSuppressor()
        let stack = try makeStack(echoSuppressor: suppressor)
        let rid = UUID()
        enqueue(stack.context, seq: 1, table: "events", op: .insert, rowID: rid)
        try stack.context.save()

        await stack.flusher.flushOnce()

        #expect(suppressor.shouldSuppress(table: "events", id: rid))
    }

    @Test("an entry with an unknown op is dropped so it can't block the queue")
    func unprocessableEntryDropped() async throws {
        let stack = try makeStack()
        let bad = OutboxEntry(sequence: 1, tableName: "events", rowID: UUID(), operation: "frobnicate", payload: Data())
        stack.context.insert(bad)
        enqueue(stack.context, seq: 2, table: "tracks", op: .insert)
        try stack.context.save()

        let outcome = await stack.flusher.flushOnce()

        #expect(outcome == .drained)
        #expect(stack.sender.sent.map(\.table) == ["tracks"]) // bad skipped, good sent
        #expect(try outbox(stack.context).isEmpty)            // both removed
    }

    // MARK: - flush() retry orchestration

    @Test("flush schedules a backoff retry that then drains the queue")
    func flushSchedulesBackoffRetryThenDrains() async throws {
        let recorder = SleepRecorder()
        let stack = try makeStack(sleep: { await recorder.record($0) })
        let rid = UUID()
        enqueue(stack.context, seq: 1, table: "events", op: .insert, rowID: rid)
        try stack.context.save()
        stack.sender.failuresRemaining = 1 // first send fails, the retry succeeds

        await stack.flusher.flush()           // flushOnce fails → schedules a retry
        await stack.flusher.retryTask?.value  // let the scheduled retry run to completion

        #expect(await recorder.delays == [1]) // one backoff of base = 1s
        #expect(stack.sender.sent.map(\.rowID) == [rid])
        #expect(try outbox(stack.context).isEmpty)
    }
}
