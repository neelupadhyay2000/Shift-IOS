import Foundation
import Models
import Services
import SwiftData

/// A value-type snapshot of one ``OutboxEntry`` — what actually gets sent to
/// Supabase. Decouples the network send from the SwiftData `@Model`.
struct OutboxItem {
    let table: String
    let rowID: UUID
    let operation: OutboxOperation
    let payload: Data?

    /// Fails if the entry's persisted `operation` string isn't a known op
    /// (treated as unprocessable by the flusher).
    init?(_ entry: OutboxEntry) {
        guard let operation = OutboxOperation(rawValue: entry.operation) else { return nil }
        self.table = entry.tableName
        self.rowID = entry.rowID
        self.operation = operation
        self.payload = entry.payload
    }
}

/// The network half of the flush, abstracted so the flusher can be unit-tested
/// with a fake. The production conformer (``SupabaseOutboxSender``) performs an
/// idempotent upsert-by-id (or delete) so re-sends never create duplicates.
@MainActor
protocol OutboxSending {
    func send(_ item: OutboxItem) async throws
}

/// The result of a single FIFO pass over the queue.
enum FlushOutcome: Equatable {
    /// The queue was emptied (every entry sent and removed).
    case drained
    /// A send failed; the head entry is retained and should be retried after the
    /// given exponential-backoff delay (seconds).
    case retry(after: TimeInterval)
}

/// Drains the Outbox to Supabase in FIFO order on reconnect.
///
/// Entries are sent in ascending ``OutboxEntry/sequence`` (the causal order
/// established at enqueue), each deleted on success. The send is an idempotent
/// upsert keyed by id, so a re-send — after a transient failure, or a crash
/// between a successful send and the local delete — converges to the same row
/// rather than duplicating it.
///
/// On the first failed send the pass **halts at the head** (a failed parent must
/// never let its children jump ahead), increments that entry's `attempts`, and
/// schedules a single deferred retry after an exponential backoff
/// (`base · 2^(attempts-1)`, capped). Successful entries ahead of the failure
/// have already been removed, so the retry resumes cleanly. Reconnect (and
/// SHIFT-612's debounce) also call ``flush()``; the single-flight guard collapses
/// overlapping triggers.
@MainActor
final class OutboxFlusher {
    private let context: ModelContext
    private let remote: any OutboxSending
    private let diagnostics: SyncDiagnosticsCenter
    private let echoSuppressor: RealtimeEchoSuppressor?
    private let baseDelay: TimeInterval
    private let maxDelay: TimeInterval
    private let sleep: @Sendable (TimeInterval) async -> Void

    private var isFlushing = false

    // nonisolated(unsafe) so the nonisolated `deinit` can cancel a pending retry;
    // every other access is on the main actor. `private(set)` so tests can await
    // the scheduled retry deterministically.
    private(set) nonisolated(unsafe) var retryTask: Task<Void, Never>?

    init(
        context: ModelContext,
        remote: any OutboxSending,
        diagnostics: SyncDiagnosticsCenter = .shared,
        echoSuppressor: RealtimeEchoSuppressor? = nil,
        baseDelay: TimeInterval = 1,
        maxDelay: TimeInterval = 60,
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    ) {
        self.context = context
        self.remote = remote
        self.diagnostics = diagnostics
        self.echoSuppressor = echoSuppressor
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.sleep = sleep
    }

    /// Flushes the queue and, if a send fails, schedules a backoff retry.
    /// Single-flight: a call while a flush is already running is a no-op (the
    /// running flush, or its scheduled retry, will pick up newly-enqueued work).
    func flush() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        if case let .retry(delay) = await flushOnce() {
            scheduleReflush(after: delay)
        }
    }

    /// One FIFO pass. Sends each entry idempotently, deleting it on success;
    /// returns `.retry` at the first failure (head-of-line halt) or `.drained`
    /// when the queue is empty. Exposed for deterministic unit testing.
    @discardableResult
    func flushOnce() async -> FlushOutcome {
        let entries = (try? context.fetch(
            FetchDescriptor<OutboxEntry>(sortBy: [SortDescriptor(\.sequence)])
        )) ?? []

        var sentCount = 0
        for entry in entries {
            guard let item = OutboxItem(entry) else {
                diagnostics.record(
                    .push, "outboxUnprocessable",
                    params: ["table": entry.tableName, "id": entry.rowID.uuidString, "op": entry.operation],
                    severity: .error
                )
                context.delete(entry)
                try? context.save()
                continue
            }

            do {
                try await remote.send(item)
                // The write has now reached Supabase — remember it so its realtime
                // echo is recognized and skipped.
                echoSuppressor?.recordLocalWrite(table: item.table, id: item.rowID)
                context.delete(entry)
                try? context.save()
                sentCount += 1
            } catch {
                entry.attempts += 1
                try? context.save()
                let delay = Self.backoffSeconds(forAttempt: entry.attempts, base: baseDelay, cap: maxDelay)
                diagnostics.record(
                    .push, "outboxFlushRetry",
                    params: [
                        "table": item.table,
                        "id": item.rowID.uuidString,
                        "attempts": String(entry.attempts),
                        "delaySeconds": String(format: "%.1f", delay),
                        "error": String(describing: error),
                    ],
                    severity: .warning
                )
                return .retry(after: delay)
            }
        }

        if sentCount > 0 {
            diagnostics.record(.push, "outboxDrained", params: ["sent": String(sentCount)])
        }
        return .drained
    }

    /// Exponential backoff in seconds: `base · 2^(attempt-1)`, capped at `cap`.
    /// `attempt` is the (1-based) number of failures so far for the entry.
    static func backoffSeconds(forAttempt attempt: Int, base: TimeInterval, cap: TimeInterval) -> TimeInterval {
        guard attempt > 0 else { return 0 }
        let raw = base * pow(2, Double(attempt - 1))
        return min(raw, cap)
    }

    private func scheduleReflush(after delay: TimeInterval) {
        retryTask?.cancel()
        retryTask = Task { @MainActor [weak self, sleep] in
            await sleep(delay)
            guard !Task.isCancelled, let self else { return }
            await self.flush()
        }
    }

    deinit {
        retryTask?.cancel()
    }
}
