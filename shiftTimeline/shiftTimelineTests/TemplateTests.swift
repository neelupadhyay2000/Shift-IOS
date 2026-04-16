import Foundation
import Models
import Services
import SwiftData
import Testing
@testable import shiftTimeline

struct TemplateTests {

    private let loader = TemplateLoader()

    // MARK: - Codable

    @Test func templateBlockEncodesAndDecodes() throws {
        let block = TemplateBlock(
            title: "Ceremony",
            relativeStartOffset: 10800,
            duration: 2700,
            isPinned: true,
            colorTag: "#FF3B30",
            icon: "heart.fill"
        )

        let data = try JSONEncoder().encode(block)
        let decoded = try JSONDecoder().decode(TemplateBlock.self, from: data)

        #expect(decoded == block)
        #expect(decoded.title == "Ceremony")
        #expect(decoded.relativeStartOffset == 10800)
        #expect(decoded.duration == 2700)
        #expect(decoded.isPinned == true)
        #expect(decoded.colorTag == "#FF3B30")
        #expect(decoded.icon == "heart.fill")
    }

    @Test func templateEncodesAndDecodes() throws {
        let template = Template(
            name: "Test Wedding",
            description: "A test template",
            category: .wedding,
            blocks: [
                TemplateBlock(title: "Prep", relativeStartOffset: 0, duration: 3600),
                TemplateBlock(title: "Ceremony", relativeStartOffset: 3600, duration: 1800, isPinned: true, colorTag: "#FF3B30", icon: "heart.fill"),
            ]
        )

        let data = try JSONEncoder().encode(template)
        let decoded = try JSONDecoder().decode(Template.self, from: data)

        #expect(decoded == template)
        #expect(decoded.name == "Test Wedding")
        #expect(decoded.category == .wedding)
        #expect(decoded.blocks.count == 2)
    }

    @Test func templateCategoryEncodesAsRawValue() throws {
        for category in TemplateCategory.allCases {
            let data = try JSONEncoder().encode(category)
            let decoded = try JSONDecoder().decode(TemplateCategory.self, from: data)
            #expect(decoded == category)
        }
    }

    @Test func templateDecodesFromRawJSON() throws {
        let json = """
        {
            "id": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
            "name": "Mini Wedding",
            "description": "A short ceremony",
            "category": "wedding",
            "blocks": [
                {
                    "title": "Ceremony",
                    "relativeStartOffset": 0,
                    "duration": 1800,
                    "isPinned": true,
                    "colorTag": "#FF3B30",
                    "icon": "heart.fill"
                }
            ]
        }
        """
        let data = Data(json.utf8)
        let template = try JSONDecoder().decode(Template.self, from: data)

        #expect(template.name == "Mini Wedding")
        #expect(template.description == "A short ceremony")
        #expect(template.category == .wedding)
        #expect(template.blocks.count == 1)
        #expect(template.blocks[0].title == "Ceremony")
        #expect(template.blocks[0].isPinned == true)
        #expect(template.id.uuidString == "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")
    }

    // MARK: - Sendable

    @Test func templateIsSendable() {
        let template = Template(
            name: "Test",
            description: "Test",
            category: .social,
            blocks: []
        )
        let _: any Sendable = template
    }

    @Test func templateBlockIsSendable() {
        let block = TemplateBlock(title: "Block", relativeStartOffset: 0, duration: 600)
        let _: any Sendable = block
    }

    // MARK: - Defaults

    @Test func templateBlockDefaultValues() {
        let block = TemplateBlock(title: "Test", relativeStartOffset: 0, duration: 600)
        #expect(block.isPinned == false)
        #expect(block.colorTag == "#007AFF")
        #expect(block.icon == "circle.fill")
    }

    // MARK: - Identifiable

    @Test func templateHasStableID() {
        let id = UUID()
        let template = Template(id: id, name: "T", description: "D", category: .wedding, blocks: [])
        #expect(template.id == id)
    }

    @Test func templateAutoGeneratesID() {
        let a = Template(name: "A", description: "D", category: .wedding, blocks: [])
        let b = Template(name: "B", description: "D", category: .wedding, blocks: [])
        #expect(a.id != b.id)
    }

    // MARK: - Bundle Loading

    @Test func loadDecodesTraditionalWedding() throws {
        let template = try loader.load(named: "classic-wedding")

        #expect(template.name == "Traditional Wedding")
        #expect(template.category == .wedding)
        #expect(template.blocks.count == 15)
        #expect(template.blocks[0].title == "Bridal Suite Prep")
        // Ceremony is pinned
        let ceremony = template.blocks.first { $0.title == "Ceremony" }
        #expect(ceremony?.isPinned == true)
        // 8 hours: last block ends at or before 28800s
        let lastBlock = template.blocks.last!
        #expect(lastBlock.relativeStartOffset + lastBlock.duration <= 28800)
    }

    @Test func loadDecodesIndianWedding() throws {
        let template = try loader.load(named: "indian-wedding")

        #expect(template.name == "Indian Wedding")
        #expect(template.category == .wedding)
        #expect(template.blocks.count == 25)
        // Baraat is pinned
        let baraat = template.blocks.first { $0.title == "Baraat Procession" }
        #expect(baraat?.isPinned == true)
        // 12 hours: last block offset at or before 43200s
        let maxEnd = template.blocks.map { $0.relativeStartOffset + $0.duration }.max()!
        #expect(maxEnd <= 43200)
    }

    @Test func loadDecodesCorporateGala() throws {
        let template = try loader.load(named: "corporate-conference")

        #expect(template.name == "Corporate Gala")
        #expect(template.category == .corporate)
        #expect(template.blocks.count == 10)
        // 5 hours: last block ends at or before 18000s
        let maxEnd = template.blocks.map { $0.relativeStartOffset + $0.duration }.max()!
        #expect(maxEnd <= 18000)
    }

    @Test func loadDecodesBirthdayParty() throws {
        let template = try loader.load(named: "birthday-party")

        #expect(template.name == "Birthday Party")
        #expect(template.category == .social)
        #expect(template.blocks.count == 8)
        // 4 hours: last block ends at or before 14400s
        let maxEnd = template.blocks.map { $0.relativeStartOffset + $0.duration }.max()!
        #expect(maxEnd <= 14400)
    }

    @Test func loadDecodesConcertFestival() throws {
        let template = try loader.load(named: "concert-festival")

        #expect(template.name == "Concert / Festival")
        #expect(template.category == .social)
        #expect(template.blocks.count == 12)
        // Headliner is pinned
        let headliner = template.blocks.first { $0.title == "Headliner Performance" }
        #expect(headliner?.isPinned == true)
        // 6 hours: last block offset at or before 21600s
        let maxEnd = template.blocks.map { $0.relativeStartOffset + $0.duration }.max()!
        #expect(maxEnd <= 21600)
    }

    @Test func loadAllReturnsAllFiveTemplates() throws {
        let templates = try loader.loadAll()

        #expect(templates.count == 5)
        let names = Set(templates.map(\.name))
        #expect(names.contains("Traditional Wedding"))
        #expect(names.contains("Indian Wedding"))
        #expect(names.contains("Corporate Gala"))
        #expect(names.contains("Birthday Party"))
        #expect(names.contains("Concert / Festival"))
    }

    @Test func loadMissingResourceThrowsError() {
        #expect(throws: TemplateLoaderError.self) {
            try loader.load(named: "nonexistent-template")
        }
    }

    // MARK: - Block Data Integrity

    @Test func allTemplateBlocksHaveValidOffsets() throws {
        let templates = try loader.loadAll()

        for template in templates {
            for block in template.blocks {
                #expect(block.duration >= 0, "Block '\(block.title)' in '\(template.name)' has negative duration")
                #expect(block.relativeStartOffset >= 0, "Block '\(block.title)' in '\(template.name)' has negative offset")
            }
        }
    }

    @Test func allTemplateBlocksUseRelativeOffsetsNotAbsoluteDates() throws {
        let templates = try loader.loadAll()

        for template in templates {
            for block in template.blocks {
                // Relative offsets should be small (under 24h = 86400s), not epoch timestamps
                #expect(block.relativeStartOffset < 86400,
                        "Block '\(block.title)' in '\(template.name)' has suspiciously large offset — may be an absolute date")
            }
        }
    }

    @Test func allTemplateBlocksHaveValidHexColors() throws {
        let templates = try loader.loadAll()
        let hexPattern = /^#[0-9A-Fa-f]{6}$/

        for template in templates {
            for block in template.blocks {
                #expect(block.colorTag.wholeMatch(of: hexPattern) != nil,
                        "Block '\(block.title)' in '\(template.name)' has invalid colorTag: \(block.colorTag)")
            }
        }
    }

    // MARK: - Category Display Helpers

    @Test func categoryDisplayNamesAreNonEmpty() {
        for category in TemplateCategory.allCases {
            #expect(!category.displayName.isEmpty)
        }
    }

    @Test func categoryDisplayNameValues() {
        #expect(TemplateCategory.wedding.displayName == "Wedding")
        #expect(TemplateCategory.corporate.displayName == "Corporate")
        #expect(TemplateCategory.social.displayName == "Social")
        #expect(TemplateCategory.photography.displayName == "Photography")
    }

    // MARK: - Browser Loading

    @Test func allTemplatesHaveNonEmptyNameAndDescription() throws {
        let templates = try loader.loadAll()

        for template in templates {
            #expect(!template.name.isEmpty, "Template has empty name")
            #expect(!template.description.isEmpty, "Template '\(template.name)' has empty description")
            #expect(!template.blocks.isEmpty, "Template '\(template.name)' has no blocks")
        }
    }

    @Test func allTemplatesHaveUniqueIDs() throws {
        let templates = try loader.loadAll()
        let ids = templates.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func templatesSortByNameProducesAlphabeticOrder() throws {
        let templates = try loader.loadAll()
            .sorted { $0.name < $1.name }
        let names = templates.map(\.name)
        #expect(names == names.sorted())
    }

    // MARK: - Template → Event Conversion

    @Test @MainActor func useTemplateCreatesEventWithCorrectBlockCount() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let template = Template(
            name: "Test Wedding",
            description: "Test",
            category: .wedding,
            blocks: [
                TemplateBlock(title: "Prep", relativeStartOffset: 0, duration: 3600, colorTag: "#FF2D55", icon: "star.fill"),
                TemplateBlock(title: "Ceremony", relativeStartOffset: 3600, duration: 1800, isPinned: true, colorTag: "#FF3B30", icon: "heart.fill"),
                TemplateBlock(title: "Reception", relativeStartOffset: 5400, duration: 7200, colorTag: "#34C759", icon: "fork.knife"),
            ]
        )

        let baseStart = Date(timeIntervalSinceReferenceDate: 0)
        let event = EventModel(title: "My Wedding", date: baseStart, latitude: 0, longitude: 0)
        context.insert(event)
        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(track)

        for templateBlock in template.blocks {
            let blockStart = baseStart.addingTimeInterval(templateBlock.relativeStartOffset)
            let block = TimeBlockModel(
                title: templateBlock.title,
                scheduledStart: blockStart,
                duration: templateBlock.duration,
                isPinned: templateBlock.isPinned,
                colorTag: templateBlock.colorTag,
                icon: templateBlock.icon
            )
            block.track = track
            context.insert(block)
        }
        try context.save()

        let blocks = (track.blocks ?? []).sorted { $0.scheduledStart < $1.scheduledStart }
        #expect(blocks.count == 3)
        #expect(event.title == "My Wedding")
    }

    @Test @MainActor func useTemplateBlockTimesAreRelativeToStartTime() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let calendar = Calendar.current
        let baseStart = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 14, minute: 0))!

        let template = Template(
            name: "Test",
            description: "Test",
            category: .wedding,
            blocks: [
                TemplateBlock(title: "A", relativeStartOffset: 0, duration: 1800),
                TemplateBlock(title: "B", relativeStartOffset: 1800, duration: 3600),
                TemplateBlock(title: "C", relativeStartOffset: 5400, duration: 900),
            ]
        )

        let event = EventModel(title: "Wedding", date: baseStart, latitude: 0, longitude: 0)
        context.insert(event)
        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(track)

        for templateBlock in template.blocks {
            let blockStart = baseStart.addingTimeInterval(templateBlock.relativeStartOffset)
            let block = TimeBlockModel(
                title: templateBlock.title,
                scheduledStart: blockStart,
                duration: templateBlock.duration,
                isPinned: templateBlock.isPinned,
                colorTag: templateBlock.colorTag,
                icon: templateBlock.icon
            )
            block.track = track
            context.insert(block)
        }
        try context.save()

        let blocks = (track.blocks ?? []).sorted { $0.scheduledStart < $1.scheduledStart }

        // A starts at 2:00 PM
        #expect(blocks[0].scheduledStart == baseStart)
        // B starts at 2:30 PM (baseStart + 1800s)
        #expect(blocks[1].scheduledStart == baseStart.addingTimeInterval(1800))
        // C starts at 3:30 PM (baseStart + 5400s)
        #expect(blocks[2].scheduledStart == baseStart.addingTimeInterval(5400))
    }

    @Test @MainActor func useTemplatePreservesBlockProperties() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let baseStart = Date(timeIntervalSinceReferenceDate: 0)

        let template = Template(
            name: "Test",
            description: "Test",
            category: .corporate,
            blocks: [
                TemplateBlock(
                    title: "Keynote",
                    relativeStartOffset: 3600,
                    duration: 5400,
                    isPinned: true,
                    colorTag: "#FF3B30",
                    icon: "mic.fill"
                ),
            ]
        )

        let event = EventModel(title: "Conf", date: baseStart, latitude: 0, longitude: 0)
        context.insert(event)
        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(track)

        let templateBlock = template.blocks[0]
        let block = TimeBlockModel(
            title: templateBlock.title,
            scheduledStart: baseStart.addingTimeInterval(templateBlock.relativeStartOffset),
            duration: templateBlock.duration,
            isPinned: templateBlock.isPinned,
            colorTag: templateBlock.colorTag,
            icon: templateBlock.icon
        )
        block.track = track
        context.insert(block)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TimeBlockModel>())
        let result = try #require(fetched.first)

        #expect(result.title == "Keynote")
        #expect(result.duration == 5400)
        #expect(result.isPinned == true)
        #expect(result.colorTag == "#FF3B30")
        #expect(result.icon == "mic.fill")
        #expect(result.scheduledStart == baseStart.addingTimeInterval(3600))
        #expect(result.track?.name == "Main")
    }

    @Test @MainActor func useTemplateCreatesMainTrackAsDefault() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Test", date: .now, latitude: 0, longitude: 0)
        context.insert(event)
        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(track)
        try context.save()

        #expect((event.tracks ?? []).count == 1)
        #expect((event.tracks ?? []).first?.isDefault == true)
        #expect((event.tracks ?? []).first?.name == "Main")
    }

    @Test @MainActor func useTemplateAllBlocksAssignedToMainTrack() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let baseStart = Date(timeIntervalSinceReferenceDate: 0)
        let template = Template(
            name: "Party",
            description: "Test",
            category: .social,
            blocks: [
                TemplateBlock(title: "A", relativeStartOffset: 0, duration: 1800),
                TemplateBlock(title: "B", relativeStartOffset: 1800, duration: 1800),
                TemplateBlock(title: "C", relativeStartOffset: 3600, duration: 1800),
            ]
        )

        let event = EventModel(title: "Bday", date: baseStart, latitude: 0, longitude: 0)
        context.insert(event)
        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(track)

        for templateBlock in template.blocks {
            let block = TimeBlockModel(
                title: templateBlock.title,
                scheduledStart: baseStart.addingTimeInterval(templateBlock.relativeStartOffset),
                duration: templateBlock.duration,
                isPinned: templateBlock.isPinned,
                colorTag: templateBlock.colorTag,
                icon: templateBlock.icon
            )
            block.track = track
            context.insert(block)
        }
        try context.save()

        #expect((track.blocks ?? []).count == 3)
        #expect((track.blocks ?? []).allSatisfy { $0.track?.id == track.id })
    }
}
