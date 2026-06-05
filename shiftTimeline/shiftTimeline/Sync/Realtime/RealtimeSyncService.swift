import Foundation
import Supabase

/// Opens one Supabase Realtime channel per active event, scoped to that event's
/// rows, and surfaces every INSERT / UPDATE / DELETE as a single merged
/// `AsyncStream` of ``RealtimeChange``.
///
/// A device subscribes only to the event it is viewing, so it receives just
/// that event's changes. Applying changes to SwiftData is SHIFT-597; echo
/// suppression SHIFT-598; foreground/background lifecycle SHIFT-599.
nonisolated struct RealtimeSyncService {

    /// One Realtime postgres-changes subscription per table, filtered on the
    /// column that carries the event id: `id` for `events` itself, the
    /// denormalized `event_id` on every child/junction table.
    nonisolated struct TableSubscription {
        let table: String
        let filterColumn: String
    }

    static let subscribedTables: [TableSubscription] = [
        TableSubscription(table: "events", filterColumn: "id"),
        TableSubscription(table: "tracks", filterColumn: "event_id"),
        TableSubscription(table: "blocks", filterColumn: "event_id"),
        TableSubscription(table: "event_vendors", filterColumn: "event_id"),
        TableSubscription(table: "block_vendors", filterColumn: "event_id"),
        TableSubscription(table: "block_dependencies", filterColumn: "event_id"),
        TableSubscription(table: "shift_records", filterColumn: "event_id"),
    ]

    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    /// Opens and subscribes a channel scoped to `eventID`, returning every row
    /// change across the event's tables as one merged stream. The channel is
    /// torn down (unsubscribed) when the stream's consumer stops or is cancelled.
    func changes(forEvent eventID: UUID) -> AsyncStream<RealtimeChange> {
        let channel = client.channel("event:\(eventID.uuidString)")

        // Register one postgres-changes binding per table (filtered to this
        // event) and tag each emitted action with its table.
        let perTable: [AsyncStream<RealtimeChange>] = Self.subscribedTables.map { subscription in
            let actions = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: subscription.table,
                filter: .eq(subscription.filterColumn, value: eventID.uuidString)
            )
            let table = subscription.table
            return AsyncStream { continuation in
                let task = Task {
                    for await action in actions {
                        continuation.yield(RealtimeChange(table: table, action: action))
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }

        let merged = mergeStreams(perTable)

        // Subscribe once all bindings are registered; forward the merged stream
        // to the consumer; unsubscribe on teardown.
        return AsyncStream { continuation in
            let subscribeTask = Task { await channel.subscribe() }
            let forwardTask = Task {
                for await change in merged {
                    continuation.yield(change)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                subscribeTask.cancel()
                forwardTask.cancel()
                Task { await channel.unsubscribe() }
            }
        }
    }
}

/// Fans several `AsyncStream`s into one: every element of every source is
/// forwarded, the merged stream finishes once all sources finish, and
/// cancelling the merged stream cancels the sources.
nonisolated func mergeStreams<Element: Sendable>(
    _ streams: [AsyncStream<Element>]
) -> AsyncStream<Element> {
    AsyncStream { continuation in
        let task = Task {
            await withTaskGroup(of: Void.self) { group in
                for stream in streams {
                    group.addTask {
                        for await element in stream {
                            continuation.yield(element)
                        }
                    }
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
