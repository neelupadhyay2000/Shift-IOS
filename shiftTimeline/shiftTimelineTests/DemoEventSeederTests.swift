import Foundation
import Models
import Services
import SwiftData
import Testing
@testable import shiftTimeline

/// Covers seeding the first-run demo event: one event, one track, template
/// blocks anchored at "now" so Go Live shows a running countdown immediately.
@MainActor
struct DemoEventSeederTests {

    /// Keeps the `ModelContainer` alive for the duration of a test.
    /// `ModelContext` does not retain its container — letting the container
    /// deallocate crashes the next insert with EXC_BREAKPOINT inside SwiftData.
    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let eventRepo: any EventRepositing
        let trackRepo: any TrackRepositing
        let blockRepo: any BlockRepositing
    }

    private func makeFixture() throws -> Fixture {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        return Fixture(
            container: container,
            context: context,
            eventRepo: SwiftDataEventRepository(context: context),
            trackRepo: SwiftDataTrackRepository(context: context),
            blockRepo: SwiftDataBlockRepository(context: context)
        )
    }

    @Test func seedCreatesEventWithTrackAndBlocks() async throws {
        let fixture = try makeFixture()
        let now = Date.now

        let eventID = await DemoEventSeeder.seed(
            eventRepo: fixture.eventRepo,
            trackRepo: fixture.trackRepo,
            blockRepo: fixture.blockRepo,
            now: now
        )

        let events = try fixture.context.fetch(FetchDescriptor<EventModel>())
        #expect(events.count == 1)
        #expect(events.first?.id == eventID)
        #expect(events.first?.title.isEmpty == false)

        let blocks = (events.first?.tracks ?? []).flatMap { $0.blocks ?? [] }
        #expect(!blocks.isEmpty)
    }

    @Test func seededBlocksStartAtNow() async throws {
        let fixture = try makeFixture()
        let now = Date.now

        _ = await DemoEventSeeder.seed(
            eventRepo: fixture.eventRepo,
            trackRepo: fixture.trackRepo,
            blockRepo: fixture.blockRepo,
            now: now
        )

        let events = try fixture.context.fetch(FetchDescriptor<EventModel>())
        let blocks = (events.first?.tracks ?? [])
            .flatMap { $0.blocks ?? [] }
            .sorted { $0.scheduledStart < $1.scheduledStart }

        // The first block starts at the seed moment so the live dashboard has
        // an active block with a real countdown the instant the user goes live.
        #expect(blocks.first?.scheduledStart == now)
    }

    @Test func fallbackTemplateHasUsableBlocks() {
        let template = DemoEventSeeder.fallbackTemplate
        #expect(!template.blocks.isEmpty)
        #expect(template.blocks.first?.relativeStartOffset == 0)
    }
}
