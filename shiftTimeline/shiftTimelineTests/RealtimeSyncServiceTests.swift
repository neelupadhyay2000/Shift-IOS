import Foundation
@testable import shiftTimeline
import Testing

@Suite("RealtimeSyncService")
struct RealtimeSyncServiceTests {

    // MARK: - Per-event channel filtering

    @Test("subscribes to the whole event graph, filtered by the event id")
    func subscribedTablesFilteredByEventID() {
        let tables = RealtimeSyncService.subscribedTables

        #expect(tables.map(\.table).sorted() == [
            "block_dependencies",
            "block_vendors",
            "blocks",
            "event_vendors",
            "events",
            "shift_records",
            "tracks",
        ])
        // `events` filters on its own primary key; every child/junction filters
        // on the denormalized `event_id`.
        #expect(tables.first { $0.table == "events" }?.filterColumn == "id")
        #expect(tables.filter { $0.table != "events" }.allSatisfy { $0.filterColumn == "event_id" })
    }

    // MARK: - mergeStreams

    @Test("merges every source element and finishes once all sources finish")
    func mergeForwardsAllElements() async {
        let (first, firstContinuation) = AsyncStream<Int>.makeStream()
        let (second, secondContinuation) = AsyncStream<Int>.makeStream()
        firstContinuation.yield(1)
        firstContinuation.yield(3)
        firstContinuation.finish()
        secondContinuation.yield(2)
        secondContinuation.yield(4)
        secondContinuation.finish()

        var received: [Int] = []
        for await value in mergeStreams([first, second]) {
            received.append(value)
        }

        #expect(received.sorted() == [1, 2, 3, 4])
    }

    @Test("merging no streams finishes immediately with nothing")
    func mergeOfNoStreamsFinishes() async {
        var received: [Int] = []
        for await value in mergeStreams([AsyncStream<Int>]()) {
            received.append(value)
        }
        #expect(received.isEmpty)
    }

    @Test("a single source merges through unchanged")
    func mergeOfSingleStream() async {
        let (stream, continuation) = AsyncStream<Int>.makeStream()
        continuation.yield(7)
        continuation.yield(8)
        continuation.finish()

        var received: [Int] = []
        for await value in mergeStreams([stream]) {
            received.append(value)
        }
        #expect(received == [7, 8])
    }

    // MARK: - Structural

    @Test("initializes with a Supabase client")
    @MainActor
    func initializesWithClient() throws {
        let url = try #require(URL(string: "https://wrhrpyinkcopqsibmkrf.supabase.co"))
        let provider = SupabaseClientProvider(supabaseURL: url, supabaseKey: "test-anon-key")
        _ = RealtimeSyncService(client: provider.client)
    }
}
