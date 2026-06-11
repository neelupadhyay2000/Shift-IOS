import Foundation
import Models

/// Persists user-created templates as JSON files on disk.
///
/// Each template lives in its own `<uuid>.json` file inside the store
/// directory (Application Support/UserTemplates by default), mirroring the
/// bundled template format so `Template` round-trips unchanged. Saving with
/// an existing ID overwrites the file, which makes `save` double as update.
///
/// User templates stay local for now; when community templates land they
/// become the upload source, so the storage format is deliberately identical
/// to the bundled starter templates.
public struct UserTemplateStore: Sendable {

    public enum StoreError: Error, Sendable, LocalizedError {
        case templateNotFound(UUID)

        public var errorDescription: String? {
            switch self {
            case .templateNotFound(let id):
                return "Template \(id.uuidString) could not be found."
            }
        }
    }

    private let directory: URL

    /// - Parameter directory: Overrides the storage directory (used by tests).
    ///   Defaults to `Application Support/UserTemplates`.
    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? FileManager.default.temporaryDirectory
            self.directory = base.appendingPathComponent("UserTemplates", isDirectory: true)
        }
    }

    /// All saved templates, sorted by name for stable display order.
    /// Returns an empty array when nothing has been saved yet.
    public func loadAll() throws -> [Template] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        let decoder = JSONDecoder()
        return try urls
            .map { try decoder.decode(Template.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The template with the given ID, or `nil` when none is saved.
    public func load(id: UUID) throws -> Template? {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Template.self, from: Data(contentsOf: url))
    }

    /// Saves a template, overwriting any existing template with the same ID.
    public func save(_ template: Template) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(template)
        try data.write(to: fileURL(for: template.id), options: .atomic)
    }

    /// Deletes the template with the given ID.
    /// - Throws: `StoreError.templateNotFound` when no such template exists.
    public func delete(id: UUID) throws {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StoreError.templateNotFound(id)
        }
        try FileManager.default.removeItem(at: url)
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}
