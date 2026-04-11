import Engine
import Foundation
import Models
import Testing

struct DependencyResolverTests {

    @Test @MainActor func resolveReturnsEmptySetForPlaceholder() {
        let resolver = DependencyResolver()
        let start = Date()

        let blocks = [
            TimeBlockModel(title: "A", scheduledStart: start, duration: 600),
            TimeBlockModel(title: "B", scheduledStart: start.addingTimeInterval(600), duration: 600),
            TimeBlockModel(title: "C", scheduledStart: start.addingTimeInterval(1200), duration: 600)
        ]

        let result = resolver.resolve(blocks: blocks, shiftedBlockID: blocks[0].id)

        switch result {
        case .success(let dependentIDs):
            #expect(dependentIDs.isEmpty)
        case .failure(let error):
            Issue.record("Expected success but got error: \(error)")
        }
    }

    @Test func resolveReturnsSuccessForEmptyBlocks() {
        let resolver = DependencyResolver()

        let result = resolver.resolve(blocks: [], shiftedBlockID: UUID())

        switch result {
        case .success(let dependentIDs):
            #expect(dependentIDs.isEmpty)
        case .failure(let error):
            Issue.record("Expected success but got error: \(error)")
        }
    }

    @Test func dependencyResolverIsSendable() {
        let resolver = DependencyResolver()
        let _: any Sendable = resolver
        _ = resolver
    }
}
