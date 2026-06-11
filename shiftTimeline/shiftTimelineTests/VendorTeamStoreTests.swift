import Foundation
import Models
import Services
import Testing
@testable import shiftTimeline

/// Covers the on-disk vendor team store: save/load round-trips, overwrite-on-save
/// (edit), delete, and behaviour against an empty or missing directory.
struct VendorTeamStoreTests {

    /// Each test gets its own throwaway directory so tests are order-independent.
    private func makeStore() -> (store: VendorTeamStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vendor-team-store-tests-\(UUID().uuidString)", isDirectory: true)
        return (VendorTeamStore(directory: directory), directory)
    }

    private func makeTeam(id: UUID = UUID(), name: String = "Wedding A-Team") -> VendorTeam {
        VendorTeam(
            id: id,
            name: name,
            members: [
                VendorTeamMember(name: "Ana Reyes", role: .photographer, phone: "555-0100", email: "ana@example.com"),
                VendorTeamMember(name: "DJ Marco", role: .dj, phone: "555-0101"),
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

        let team = makeTeam()
        try store.save(team)

        let loaded = try store.loadAll()
        #expect(loaded == [team])
        #expect(loaded.first?.members.count == 2)
    }

    @Test func saveWithExistingIDOverwrites() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = makeTeam(name: "Original Crew")
        try store.save(original)

        var edited = original
        edited.name = "Renamed Crew"
        edited.members.removeLast()
        try store.save(edited)

        let loaded = try store.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded.first?.name == "Renamed Crew")
        #expect(loaded.first?.members.count == 1)
    }

    @Test func deleteRemovesTeam() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let team = makeTeam()
        try store.save(team)
        try store.delete(id: team.id)

        #expect(try store.loadAll().isEmpty)
    }

    @Test func deleteMissingTeamThrows() {
        let (store, _) = makeStore()
        #expect(throws: VendorTeamStore.StoreError.self) {
            try store.delete(id: UUID())
        }
    }

    @Test func loadAllSortsByNameCaseInsensitively() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try store.save(makeTeam(name: "zeta Crew"))
        try store.save(makeTeam(name: "Alpha Crew"))

        #expect(try store.loadAll().map(\.name) == ["Alpha Crew", "zeta Crew"])
    }

    @Test func decodesTeamsSavedBeforeCustomRoleLabelExisted() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        // A team file written before `customRoleLabel` was added — the member
        // has no such key. Decoding must not fail (defaults to "").
        let id = UUID()
        let legacyJSON = """
        {
            "id": "\(id.uuidString)",
            "name": "Legacy Crew",
            "members": [
                {
                    "id": "\(UUID().uuidString)",
                    "name": "Ana Reyes",
                    "role": "photographer",
                    "phone": "",
                    "email": ""
                }
            ]
        }
        """
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(legacyJSON.utf8).write(to: directory.appendingPathComponent("\(id.uuidString).json"))

        let loaded = try store.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded.first?.members.first?.customRoleLabel == "")
    }

    @Test func customRoleLabelRoundTrips() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let team = VendorTeam(
            name: "Film Crew",
            members: [VendorTeamMember(name: "Lia", role: .custom, customRoleLabel: "Videographer")]
        )
        try store.save(team)

        let loaded = try store.loadAll()
        #expect(loaded.first?.members.first?.customRoleLabel == "Videographer")
    }

    @Test func persistsAcrossStoreInstances() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let team = makeTeam()
        try store.save(team)

        let secondInstance = VendorTeamStore(directory: directory)
        #expect(try secondInstance.loadAll() == [team])
    }
}
