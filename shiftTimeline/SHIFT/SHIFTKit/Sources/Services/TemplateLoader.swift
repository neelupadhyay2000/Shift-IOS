import Foundation
import Models

/// Loads bundled Template JSON files from a given bundle.
public struct TemplateLoader: Sendable {

    public init() {}

    /// Loads all templates from JSON files in the bundle's "Templates" directory.
    /// - Parameter bundle: The bundle containing the JSON resources. Defaults to the package's resource bundle.
    /// - Returns: An array of decoded `Template` values.
    public func loadAll(from bundle: Bundle? = nil) throws -> [Template] {
        let resolvedBundle = bundle ?? .module
        let urls: [URL]
        if let subdirURLs = resolvedBundle.urls(forResourcesWithExtension: "json", subdirectory: "Templates"),
           !subdirURLs.isEmpty {
            urls = subdirURLs
        } else if let rootURLs = resolvedBundle.urls(forResourcesWithExtension: "json", subdirectory: nil),
                  !rootURLs.isEmpty {
            urls = rootURLs
        } else {
            return []
        }
        let decoder = JSONDecoder()
        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(Template.self, from: data)
        }
    }

    /// Loads a single template from a named JSON resource.
    public func load(named resourceName: String, from bundle: Bundle? = nil) throws -> Template {
        let resolvedBundle = bundle ?? .module
        let url = resolvedBundle.url(forResource: resourceName, withExtension: "json", subdirectory: "Templates")
            ?? resolvedBundle.url(forResource: resourceName, withExtension: "json")
        guard let url else {
            throw TemplateLoaderError.resourceNotFound(resourceName)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Template.self, from: data)
    }

    /// Loads all templates from a directory on disk.
    public func loadAll(from directory: URL) throws -> [Template] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
        let decoder = JSONDecoder()
        return try contents.map { url in
            let data = try Data(contentsOf: url)
            return try decoder.decode(Template.self, from: data)
        }
    }

    /// Loads a single template from a named JSON file in a directory on disk.
    public func load(named resourceName: String, from directory: URL) throws -> Template {
        let url = directory.appendingPathComponent("\(resourceName).json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TemplateLoaderError.resourceNotFound(resourceName)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Template.self, from: data)
    }
}

public enum TemplateLoaderError: Error, Sendable {
    case resourceNotFound(String)
}
