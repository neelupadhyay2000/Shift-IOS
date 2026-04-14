#if os(iOS)
import Foundation
import Models
import Services
import SwiftData
import Testing
@testable import shiftTimeline

struct PDFGeneratorTests {

    private let generator = PDFGenerator()

    private func makeBlocks(
        in context: ModelContext,
        base: Date,
        offsets: [(String, TimeInterval)]
    ) -> [TimeBlockModel] {
        offsets.map { title, offset in
            let block = TimeBlockModel(
                title: title,
                scheduledStart: base.addingTimeInterval(offset),
                duration: 1800,
                isPinned: false,
                colorTag: "#007AFF",
                icon: "star"
            )
            context.insert(block)
            return block
        }.sorted { $0.scheduledStart < $1.scheduledStart }
    }

    // MARK: - Row Ordering

    @Test @MainActor func rowsInChronologicalOrder() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let base = Date(timeIntervalSince1970: 1_750_000_000)

        let blocks = makeBlocks(in: context, base: base, offsets: [
            ("First", 0),
            ("Second", 3600),
            ("Third", 7200),
        ])

        let rows = generator.buildRows(blocks: blocks, sunsetTime: nil, goldenHourStart: nil)

        #expect(rows.count == 3)
        #expect(rows[0].title == "First")
        #expect(rows[1].title == "Second")
        #expect(rows[2].title == "Third")
    }

    // MARK: - Sunset Insertion

    @Test @MainActor func sunsetInsertedChronologically() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let base = Date(timeIntervalSince1970: 1_750_000_000)

        let blocks = makeBlocks(in: context, base: base, offsets: [
            ("Before Sunset", 0),
            ("After Sunset", 7200),
        ])

        let sunset = base.addingTimeInterval(3600) // between the two blocks
        let rows = generator.buildRows(blocks: blocks, sunsetTime: sunset, goldenHourStart: nil)

        #expect(rows.count == 3)
        #expect(rows[0].title == "Before Sunset")
        #expect(rows[1].highlight == PDFGenerator.HighlightKind.sunset)
        #expect(rows[1].title == "☀ Sunset")
        #expect(rows[2].title == "After Sunset")
    }

    // MARK: - Golden Hour Insertion

    @Test @MainActor func goldenHourInsertedChronologically() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let base = Date(timeIntervalSince1970: 1_750_000_000)

        let blocks = makeBlocks(in: context, base: base, offsets: [
            ("Block A", 0),
            ("Block B", 7200),
        ])

        let golden = base.addingTimeInterval(3600)
        let rows = generator.buildRows(blocks: blocks, sunsetTime: nil, goldenHourStart: golden)

        #expect(rows.count == 3)
        #expect(rows[1].highlight == PDFGenerator.HighlightKind.goldenHour)
        #expect(rows[1].title == "✦ Golden Hour")
    }

    // MARK: - Both Markers, Golden Hour Before Sunset

    @Test @MainActor func goldenHourBeforeSunsetBothInsertedCorrectly() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let base = Date(timeIntervalSince1970: 1_750_000_000)

        let blocks = makeBlocks(in: context, base: base, offsets: [
            ("Morning", 0),
            ("Afternoon", 3600),
            ("Evening", 10800),
        ])

        let golden = base.addingTimeInterval(5400)  // 1h30 — between Afternoon & Evening
        let sunset = base.addingTimeInterval(7200)   // 2h — also between Afternoon & Evening

        let rows = generator.buildRows(blocks: blocks, sunsetTime: sunset, goldenHourStart: golden)

        #expect(rows.count == 5)
        #expect(rows[0].title == "Morning")
        #expect(rows[1].title == "Afternoon")
        #expect(rows[2].highlight == PDFGenerator.HighlightKind.goldenHour)
        #expect(rows[3].highlight == PDFGenerator.HighlightKind.sunset)
        #expect(rows[4].title == "Evening")
    }

    // MARK: - Both Markers, Sunset Before Golden Hour (edge case)

    @Test @MainActor func sunsetBeforeGoldenHourOrderedCorrectly() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let base = Date(timeIntervalSince1970: 1_750_000_000)

        let blocks = makeBlocks(in: context, base: base, offsets: [
            ("Block", 0),
            ("Last", 10800),
        ])

        // Edge: sunset at 1h, golden at 2h (reversed from typical)
        let sunset = base.addingTimeInterval(3600)
        let golden = base.addingTimeInterval(7200)

        let rows = generator.buildRows(blocks: blocks, sunsetTime: sunset, goldenHourStart: golden)

        #expect(rows.count == 4)
        #expect(rows[0].title == "Block")
        #expect(rows[1].highlight == PDFGenerator.HighlightKind.sunset)
        #expect(rows[2].highlight == PDFGenerator.HighlightKind.goldenHour)
        #expect(rows[3].title == "Last")
    }

    // MARK: - Marker at End

    @Test @MainActor func sunsetAfterAllBlocksAppendsAtEnd() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let base = Date(timeIntervalSince1970: 1_750_000_000)

        let blocks = makeBlocks(in: context, base: base, offsets: [
            ("Only Block", 0),
        ])

        let sunset = base.addingTimeInterval(7200)
        let rows = generator.buildRows(blocks: blocks, sunsetTime: sunset, goldenHourStart: nil)

        #expect(rows.count == 2)
        #expect(rows[0].title == "Only Block")
        #expect(rows[1].highlight == PDFGenerator.HighlightKind.sunset)
    }

    // MARK: - PDF Data Output

    @Test @MainActor func generateReturnsNonEmptyPDFData() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(
            title: "Test Event",
            date: .now,
            latitude: 0,
            longitude: 0
        )
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(track)

        let block = TimeBlockModel(
            title: "Ceremony",
            scheduledStart: .now,
            duration: 1800,
            isPinned: false,
            colorTag: "#FF9500",
            icon: "heart.fill"
        )
        block.track = track
        context.insert(block)

        let data = generator.generate(from: event)

        #expect(!data.isEmpty)
        // Valid PDF starts with %PDF
        let header = String(data: data.prefix(4), encoding: .ascii)
        #expect(header == "%PDF")
    }

    // MARK: - Pinned Block Row

    @Test @MainActor func pinnedBlockMarkedInRow() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let base = Date(timeIntervalSince1970: 1_750_000_000)

        let block = TimeBlockModel(
            title: "Locked Block",
            scheduledStart: base,
            duration: 1800,
            isPinned: true,
            colorTag: "#FF0000",
            icon: "pin.fill"
        )
        context.insert(block)

        let rows = generator.buildRows(blocks: [block], sunsetTime: nil, goldenHourStart: nil)

        #expect(rows.count == 1)
        #expect(rows[0].isPinned == true)
        #expect(rows[0].highlight == PDFGenerator.HighlightKind.none)
    }
}
#endif
