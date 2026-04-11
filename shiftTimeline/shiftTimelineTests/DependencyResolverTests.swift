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
            #expect(ids == Set([blocks[1].id, blocks[2].id]))
        case .failure(let error):
            Issue.record("Expected success but got error: \(error)")
        }
    }

    // MARK: - Branching

    /// A→B, A→C (B and C are both direct dependents of A): shift A returns {B, C}
    @Test @MainActor func branchingReturnsAllDownstream() {
        let resolver = DependencyResolver()

        let a = UUID()
        let b = UUID()
        let c = UUID()

        let adjacency: [UUID: [UUID]] = [
            a: [b, c]
        ]

        let result = resolver.resolve(adjacency: adjacency, from: a)

        switch result {
        case .success(let ids):
            #expect(ids == Set([b, c]))
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

    // MARK: - Cycle Detection: Direct (A→B→A)

    @Test func directCycleDetected() {
        let resolver = DependencyResolver()
        let a = UUID()
        let b = UUID()

        let adjacency: [UUID: [UUID]] = [
            a: [b],
            b: [a]
        ]

        let result = resolver.resolve(adjacency: adjacency, from: a)

        switch result {
        case .success:
            Issue.record("Expected circularDependency error")
        case .failure(let error):
            #expect(error == .circularDependency(blockID: a))
        }
    }

    // MARK: - Cycle Detection: Indirect (A→B→C→A)

    @Test func indirectCycleDetected() {
        let resolver = DependencyResolver()
        let a = UUID()
        let b = UUID()
        let c = UUID()

        let adjacency: [UUID: [UUID]] = [
            a: [b],
            b: [c],
            c: [a]
        ]

        let result = resolver.resolve(adjacency: adjacency, from: a)

        switch result {
        case .success:
            Issue.record("Expected circularDependency error")
        case .failure(let error):
            #expect(error == .circularDependency(blockID: a))
        }
    }

    // MARK: - Cycle Detection: Self-dependency (A→A)

    @Test func selfDependencyCycleDetected() {
        let resolver = DependencyResolver()
        let a = UUID()

        let adjacency: [UUID: [UUID]] = [
            a: [a]
        ]

        let result = resolver.resolve(adjacency: adjacency, from: a)

        switch result {
        case .success:
            Issue.record("Expected circularDependency error")
        case .failure(let error):
            #expect(error == .circularDependency(blockID: a))
        }
    }

    // MARK: - No Cycle With Explicit Adjacency

    @Test func noCycleReturnsCorrectIDs() {
        let resolver = DependencyResolver()
        let a = UUID()
        let b = UUID()
        let c = UUID()

        let adjacency: [UUID: [UUID]] = [
            a: [b],
            b: [c]
        ]

        let result = resolver.resolve(adjacency: adjacency, from: a)

        switch result {
        case .success(let ids):
            #expect(ids == Set([b, c]))
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
