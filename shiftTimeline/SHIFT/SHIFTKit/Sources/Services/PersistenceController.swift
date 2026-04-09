import Foundation
import SwiftData
import Models

public final class PersistenceController: Sendable {

    public static let shared = PersistenceController()

    public let container: ModelContainer

    public static var schema: Schema {
        Schema([
            EventModel.self,
            TimeBlockModel.self,
            TimelineTrack.self,
            VendorModel.self,
            ShiftRecord.self,
        ])
    }

    private init() {
        let schema = Self.schema
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // During development, delete the stale store and retry
            let url = config.url
            let relatedFiles = [
                url,
                url.deletingPathExtension().appendingPathExtension("store-shm"),
                url.deletingPathExtension().appendingPathExtension("store-wal"),
            ]
            for file in relatedFiles {
                try? FileManager.default.removeItem(at: file)
            }
            do {
                container = try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Could not create ModelContainer after store reset: \(error)")
            }
        }
    }

    public static func forTesting() throws -> ModelContainer {
        let schema = Self.schema
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }
}
