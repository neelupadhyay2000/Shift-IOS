import Foundation
import Models
import Services
import Testing

struct TemplateTests {

    /// Directory containing the bundled template JSON files on disk.
    private static let templatesDirectory = URL(
        fileURLWithPath: #filePath
    )
    .deletingLastPathComponent()  // shiftTimelineTests/
    .deletingLastPathComponent()  // shiftTimeline/
    .appendingPathComponent("shiftTimeline/Templates")

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

    @Test func loadDecodesClassicWedding() throws {
        let loader = TemplateLoader()
        let template = try loader.load(named: "classic-wedding", from: Self.templatesDirectory)

        #expect(template.name == "Classic Wedding")
        #expect(template.category == .wedding)
        #expect(template.blocks.count == 10)
        #expect(template.blocks[0].title == "Bridal Suite Prep")
        #expect(template.blocks[2].title == "Ceremony")
        #expect(template.blocks[2].isPinned == true)
    }

    @Test func loadDecodesCorporateConference() throws {
        let loader = TemplateLoader()
        let template = try loader.load(named: "corporate-conference", from: Self.templatesDirectory)

        #expect(template.name == "Corporate Conference")
        #expect(template.category == .corporate)
        #expect(template.blocks.count == 7)
    }

    @Test func loadDecodesBirthdayParty() throws {
        let loader = TemplateLoader()
        let template = try loader.load(named: "birthday-party", from: Self.templatesDirectory)

        #expect(template.name == "Birthday Party")
        #expect(template.category == .social)
        #expect(template.blocks.count == 6)
    }

    @Test func loadAllReturnsAllTemplates() throws {
        let loader = TemplateLoader()
        let templates = try loader.loadAll(from: Self.templatesDirectory)

        #expect(templates.count >= 3)
        let names = Set(templates.map(\.name))
        #expect(names.contains("Classic Wedding"))
        #expect(names.contains("Corporate Conference"))
        #expect(names.contains("Birthday Party"))
    }

    @Test func loadMissingResourceThrowsError() {
        let loader = TemplateLoader()
        #expect(throws: TemplateLoaderError.self) {
            try loader.load(named: "nonexistent-template", from: Self.templatesDirectory)
        }
    }

    // MARK: - Block Data Integrity

    @Test func allTemplateBlocksHaveValidDurations() throws {
        let loader = TemplateLoader()
        let templates = try loader.loadAll(from: Self.templatesDirectory)

        for template in templates {
            for block in template.blocks {
                #expect(block.duration > 0, "Block '\(block.title)' in '\(template.name)' has non-positive duration")
                #expect(block.relativeStartOffset >= 0, "Block '\(block.title)' in '\(template.name)' has negative offset")
            }
        }
    }

    @Test func allTemplateBlocksHaveValidHexColors() throws {
        let loader = TemplateLoader()
        let templates = try loader.loadAll(from: Self.templatesDirectory)
        let hexPattern = /^#[0-9A-Fa-f]{6}$/

        for template in templates {
            for block in template.blocks {
                #expect(block.colorTag.wholeMatch(of: hexPattern) != nil,
                        "Block '\(block.title)' in '\(template.name)' has invalid colorTag: \(block.colorTag)")
            }
        }
    }
}
