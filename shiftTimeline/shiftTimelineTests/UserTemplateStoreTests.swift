import Foundation
import Models
import Services
import Testing
@testable import shiftTimeline

/// Covers the on-disk user template store: save/load round-trips, overwrite-on-save
/// (edit), delete, and behaviour against an empty or missing directory.
struct UserTemplateStoreTests {

    /// Each test gets its own throwaway directory so tests are order-independent.
    private func makeStore() -> (store: UserTemplateStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("user-template-store-tests-\(UUID().uuidString)", isDirectory: true)
        return (UserTemplateStore(directory: directory), directory)
    }

    private func makeTemplate(
        id: UUID = UUID(),
        name: String = "Backyard Wedding",
        description: String = "Saved from a real event"
    ) -> Template {
        Template(
            id: id,
            name: name,
            description: description,
            category: .wedding,
            blocks: [
                TemplateBlock(title: "Prep", relativeStartOffset: 0, duration: 3600),
                TemplateBlock(
                    title: "Ceremony",
                    relativeStartOffset: 3600,
                    duration: 1800,
                    isPinned: true,
                    colorTag: "#FF3B30",
                    icon: "heart.fill"
                ),
            ]
        )
    }

    @Test func loadAllReturnsEmptyWhenDirectoryDoesNotExist() throws {
        let (store, _) = makeStore()
        #expect(try store.loadAll().isEmpty)
    }

    @Test func saveThenLoadAllRoundTrips() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let template = makeTemplate()
        try store.save(template)

        let loaded = try store.loadAll()
        #expect(loaded == [template])
    }

    @Test func saveWithExistingIDOverwrites() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = makeTemplate(name: "Original Name")
        try store.save(original)

        let edited = Template(
            id: original.id,
            name: "Edited Name",
            description: original.description,
            category: .photography,
            blocks: original.blocks
        )
        try store.save(edited)

        let loaded = try store.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded.first?.name == "Edited Name")
        #expect(loaded.first?.category == .photography)
    }

    @Test func loadByIDReturnsSavedTemplate() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let template = makeTemplate()
        try store.save(template)

        #expect(try store.load(id: template.id) == template)
    }

    @Test func loadByIDReturnsNilWhenMissing() throws {
        let (store, _) = makeStore()
        #expect(try store.load(id: UUID()) == nil)
    }

    @Test func deleteRemovesTemplate() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let template = makeTemplate()
        try store.save(template)
        try store.delete(id: template.id)

        #expect(try store.loadAll().isEmpty)
        #expect(try store.load(id: template.id) == nil)
    }

    @Test func deleteMissingTemplateThrows() {
        let (store, _) = makeStore()
        #expect(throws: UserTemplateStore.StoreError.self) {
            try store.delete(id: UUID())
        }
    }

    @Test func loadAllSortsByNameCaseInsensitively() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try store.save(makeTemplate(name: "zeta Gala"))
        try store.save(makeTemplate(name: "Alpha Party"))

        let loaded = try store.loadAll()
        #expect(loaded.map(\.name) == ["Alpha Party", "zeta Gala"])
    }

    @Test func persistsAcrossStoreInstances() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let template = makeTemplate()
        try store.save(template)

        let secondInstance = UserTemplateStore(directory: directory)
        #expect(try secondInstance.loadAll() == [template])
    }
}
