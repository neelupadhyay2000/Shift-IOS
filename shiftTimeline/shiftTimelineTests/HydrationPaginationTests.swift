import Foundation
@testable import shiftTimeline
import Testing

@Suite("Hydration pagination loop")
struct HydrationPaginationTests {

    /// Returns the slice `[from, to]` (inclusive) of `items`, or `[]` past the end.
    private func page(_ items: [Int], from: Int, to: Int) -> [Int] {
        guard from < items.count else { return [] }
        return Array(items[from..<min(to + 1, items.count)])
    }

    @Test("accumulates pages until a short page ends the loop")
    func accumulatesUntilShortPage() async throws {
        let items = Array(0..<5)
        var ranges: [(Int, Int)] = []
        let result = await paginate(pageSize: 2) { from, to in
            ranges.append((from, to))
            return page(items, from: from, to: to)
        }
        #expect(result == items)
        // [0,1] [2,3] [4,5]→1 item (short) → stop.
        #expect(ranges.map(\.0) == [0, 2, 4])
        #expect(ranges.count == 3)
    }

    @Test("an exact multiple of the page size does one extra empty fetch then stops")
    func exactMultipleDoesOneEmptyFetch() async throws {
        let items = Array(0..<4)
        var fetches = 0
        let result = await paginate(pageSize: 2) { from, to in
            fetches += 1
            return page(items, from: from, to: to)
        }
        #expect(result == items)
        #expect(fetches == 3) // two full pages + one empty page
    }

    @Test("a single short first page stops immediately")
    func singleShortPageStops() async throws {
        var fetches = 0
        let result: [Int] = await paginate(pageSize: 10) { _, _ in
            fetches += 1
            return [1, 2, 3]
        }
        #expect(result == [1, 2, 3])
        #expect(fetches == 1)
    }

    @Test("an empty table fetches once and returns nothing")
    func emptyTable() async throws {
        var fetches = 0
        let result: [Int] = await paginate(pageSize: 5) { _, _ in
            fetches += 1
            return []
        }
        #expect(result.isEmpty)
        #expect(fetches == 1)
    }

    @Test("propagates a fetch error")
    func propagatesError() async {
        struct PageError: Error {}
        await #expect(throws: PageError.self) {
            _ = try await paginate(pageSize: 5) { _, _ -> [Int] in throw PageError() }
        }
    }
}
