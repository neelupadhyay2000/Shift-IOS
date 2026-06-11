import Foundation
import Models

/// Persists user-defined vendor teams as JSON files on disk.
///
/// Each team lives in its own `<uuid>.json` file inside the store directory
/// (Application Support/VendorTeams by default), mirroring `UserTemplateStore`.
/// Saving with an existing ID overwrites the file, so `save` doubles as update.
/// Teams are device-local preference data — applying one to an event creates
/// per-event `VendorModel` rows, which are what sync.
public struct VendorTeamStore: Sendable {

    public enum StoreError: Error, Sendable, LocalizedError {
        case teamNotFound(UUID)

        public var errorDescription: String? {
            switch self {
            case .teamNotFound(let id):
                return "Vendor team \(id.uuidString) could not be found."
            }
        }
    }

    private let directory: URL

    /// - Parameter directory: Overrides the storage directory (used by tests).
    ///   Defaults to `Application Support/VendorTeams`.
    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? FileManager.default.temporaryDirectory
            self.directory = base.appendingPathComponent("VendorTeams", isDirectory: true)
        }
    }

    /// All saved teams, sorted by name for stable display order.
    /// Returns an empty array when nothing has been saved yet.
    public func loadAll() throws -> [VendorTeam] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        let decoder = JSONDecoder()
        return try urls
            .map { try decoder.decode(VendorTeam.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Saves a team, overwriting any existing team with the same ID.
    public func save(_ team: VendorTeam) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(team)
        try data.write(to: fileURL(for: team.id), options: .atomic)
    }

    /// Deletes the team with the given ID.
    /// - Throws: `StoreError.teamNotFound` when no such team exists.
    public func delete(id: UUID) throws {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StoreError.teamNotFound(id)
        }
        try FileManager.default.removeItem(at: url)
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}
