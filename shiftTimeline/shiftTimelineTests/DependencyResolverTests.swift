import Engine
import Foundation
import Models
import Testing

struct DependencyResolverTests {

    // MARK: - Linear Chain

    /// A→B→C: shift A returns {B, C}
    @Test @MainActor func linearChainReturnsAllDownstream() {
        let resolver = DependencyResolver()
        let start = Date()

        let blocks = [
            TimeBlockModel(title: "A", scheduledStart: start, duration: 600),
            TimeBlockModel(title: "B", scheduledStart: start.addingTimeInterval(600), duration: 600),
            TimeBlockModel(title: "C", scheduledStart: start.addingTimeInterval(1200), duration: 600)
        ]

        let result = resolver.resolve(blocks: blocks, shiftedBlockID: blocks[0].id)

        switch result {
        case .success(let ids):
            #expect(ids == [blocks[1].id, blocks[2].id])
        case .failure(let error):
            Issue.record("Expected success but got error: \(error)")
        }
    }

    // MARK: - Branching

    /// A→B, A→C (B and C share the same scheduledStart after A): shift A returns {B, C}
    @Test @MainActor func branchingReturnsAllDownstream() {
        let resolver = DependencyResolver()
        let start = Date()

        let a = TimeBlockModel(title: "A", scheduledStart: start, duration: 600)
        let b = TimeBlockModel(title: "B", scheduledStart: start.addingTimeInterval(600), duration: 600)
        let c = TimeBlockModel(title: "C", scheduledStart: start.addingTimeInterval(1200), duration: 600)

        let result = resolver.resolve(blocks: [a, b, c], shiftedBlockID: a.id)

        switch result {
        case .success(let ids):
            #expect(ids.contains(b.id))
            #expect(ids.contains(c.id))
            #expect(ids.count == 2)
        case .failure(let error):
            Issue.record("Expected success but got error: \(error)")
        }
    }

    // MARK: - Deep Chain (5 levels)

    @Test @MainActor func deepChainReturnsAllDownstream() {
        let resolver = DependencyResolver()
        let start = Date()

        let blocks = (0..<5).map { i in
            TimeBlockModel(
                title: "Block\(i)",
                scheduledStart: start.addingTimeInterval(Double(i) * 600),
                duration: 600
            )
        }

        let result = resolver.resolve(blocks: blocks, shiftedBlockID: blocks[0].id)

        switch result {
        case .success(let ids):
            let expected = Set(blocks.dropFirst().map(\.id))
            #expect(ids == expected)
        case .failure(let error):
            Issue.record("Expected success but got error: \(error)")
        }
    }

    // MARK: - No Dependents (last block)

    @Test @MainActor func lastBlockHasNoDependents() {
        let resolver = DependencyResolver()
        let start = Date()

        let blocks = [
            TimeBlockModel(title: "A", scheduledStart: start, duration: 600),
            TimeBlockModel(title: "B", scheduledStart: start.addingTimeInterval(600), duration: 600),
            TimeBlockModel(title: "C", scheduledStart: start.addingTimeInterval(1200), duration: 600)
        ]

        let result = resolver.resolve(blocks: blocks, shiftedBlockID: blocks[2].id)

        switch result {
        case .success(let ids):
            #expect(ids.isEmpty)
        case .failure(let error):
            Issue.record("Expected success but got error: \(error)")
        }
    }

    // MARK: - Block Not In Graph

    @Test @MainActor func unknownBlockReturnsEmptySet() {
        let resolver = DependencyResolver()
        let start = Date()

        let blocks = [
            TimeBlockModel(title: "A", scheduledStart: start, duration: 600),
            TimeBlockModel(title: "B", scheduledStart: start.addingTimeInterval(600), duration: 600)
        ]

        let result = resolver.resolve(blocks: blocks, shiftedBlockID: UUID())

        switch result {
        case .success(let ids):
            #expect(ids.isEmpty)
        case .failure(let error):
            Issue.record("Expected success but got error: \(error)")
        }
    }

    // MARK: - Empty Blocks

    @Test func emptyBlocksReturnsEmptySet() {
        let resolver = DependencyResolver()

        let result = resolver.resolve(blocks: [], shiftedBlockID: UUID())

        switch result {
        case .success(let ids):
            #expect(ids.isEmpty)
        case .failure(let error):
            Issue.record("Expected success but got error: \(error)")
        }
    }

    // MARK: - Sendable

    @Test func dependencyResolverIsSendable() {
        let resolver = DependencyResolver()
        let _: any Sendable = resolver
        _ = resolver
    }
}
