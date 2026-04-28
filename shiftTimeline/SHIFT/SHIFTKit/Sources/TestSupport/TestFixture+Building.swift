import Foundation
import Models
import SwiftData

extension TestFixture: FixtureBuilding {
    @MainActor
    public func build(into context: ModelContext, clock: TestClock) throws {
        switch self {
        case .singleEventFiveBlocks:
            try SingleEventFiveBlocksBuilder().build(into: context, clock: clock)
        case .weddingTemplateApplied:
            try WeddingTemplateAppliedBuilder().build(into: context, clock: clock)
        case .multiTrackConference:
            try MultiTrackConferenceBuilder().build(into: context, clock: clock)
        case .eventWithVendors(let count):
            try EventWithVendorsBuilder(count: count).build(into: context, clock: clock)
        case .liveEventInProgress(let blockIndex):
            try LiveEventInProgressBuilder(blockIndex: blockIndex).build(into: context, clock: clock)
        case .eventWithRainForecastedBlock:
            try EventWithRainForecastedBlockBuilder().build(into: context, clock: clock)
        case .eventWithSunsetBlocks:
            try EventWithSunsetBlocksBuilder().build(into: context, clock: clock)
        }
    }
}
