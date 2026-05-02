import Foundation
import Models
import Services
import SwiftData
import Testing

/// Drift detector that fails the build whenever a stored property declared on
/// a live `@Model` type is missing from the corresponding model in
/// `SHIFTMigrationPlan.schemas.last`.
///
/// This is the exact regression class that broke CloudKit sync after SHIFT-303
/// added `TimeBlockModel.isTransitBlock` without a matching `SHIFTSchemaV5`.
/// The mirror checksum no longer matched any `VersionedSchema`, the migration
/// plan was rejected, and `NSPersistentCloudKitContainer` silently stopped
/// publishing records to iCloud.
///
/// If any of these tests fail, do NOT silence them — add a new
/// `SHIFTSchemaV{N+1}` snapshot containing the new property and append a
/// `migrateV{N}toV{N+1}` lightweight stage to `SHIFTMigrationPlan`.
@Suite("CloudKit Sync Integrity")
struct CloudKitSyncIntegrityTests {

    // MARK: - Helpers

    private static func liveModels() -> [any PersistentModel.Type] {
        [
            EventModel.self,
            TimeBlockModel.self,
            TimelineTrack.self,
            VendorModel.self,
            ShiftRecord.self,
        ]
    }

    /// Builds a name → property-set map from a list of models. Uses a single
    /// `Schema(...)` so SwiftData resolves all relationships in one graph and
    /// `entities` returns one `Entity` per model — keyed by `Entity.name`,
    /// which is the unqualified model class name (e.g. `"TimeBlockModel"`).
    private static func storedPropertyNamesByEntity(
        for models: [any PersistentModel.Type]
    ) -> [String: Set<String>] {
        let schema = Schema(models)
        var dict: [String: Set<String>] = [:]
        for entity in schema.entities {
            let attributes = entity.attributes.map(\.name)
            let relationships = entity.relationships.map(\.name)
            dict[entity.name] = Set(attributes).union(relationships)
        }
        return dict
    }

    // MARK: - Drift Detector

    /// Every stored property on every live `@Model` must also exist on the
    /// matching model inside the latest `VersionedSchema` snapshot.
    @Test func liveModelMatchesLatestVersionedSchema() {
        let livePropsByName = Self.storedPropertyNamesByEntity(for: Self.liveModels())
        let snapshotPropsByName = Self.storedPropertyNamesByEntity(
            for: SHIFTMigrationPlan.schemas.last?.models ?? []
        )

        for (entityName, liveProps) in livePropsByName {
            guard let snapshotProps = snapshotPropsByName[entityName] else {
                Issue.record("Live model `\(entityName)` is missing from the latest VersionedSchema in SHIFTMigrationPlan")
                continue
            }

            let missing = liveProps.subtracting(snapshotProps)
            #expect(
                missing.isEmpty,
                "Live `\(entityName)` declares stored properties absent from the latest VersionedSchema: \(missing.sorted()). Add a new SHIFTSchemaV{N+1} snapshot containing these properties and a corresponding lightweight MigrationStage."
            )
        }
    }

    // MARK: - CloudKit Conflict Resolution

    /// Simulates a last-write-wins merge conflict on a shared on-disk store.
    ///
    /// ## What this tests
    /// `NSPersistentCloudKitContainer` — the backing engine of SwiftData's
    /// `.automatic` CloudKit database — resolves merge conflicts using
    /// last-write-wins: the mutation with the latest `CKRecord.modificationDate`
    /// (set by CloudKit on each `save`) is the one that survives a sync cycle.
    ///
    /// Because real CloudKit sync requires network entitlements and a running
    /// iCloud account (neither available in CI), this test verifies the
    /// **observable on-disk contract** using two separate `ModelContainer`
    /// instances that point to the same SQLite store (no CloudKit networking,
    /// `cloudKitDatabase: .none`). The last `context.save()` to reach the
    /// WAL checkpoint wins — exactly the same ordering semantics CloudKit uses
    /// when it merges remote records into the local store.
    ///
    /// If this test ever fails it means SwiftData's merge policy has changed
    /// and `PersistenceController`'s conflict strategy comment needs updating.
    @Test func lastWriteWinsOnConcurrentOfflineMutation() throws {
        // Build a shared temp store that both containers will open.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let storeURL = tempDir.appendingPathComponent("conflict_test.store")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let schema = Schema([EventModel.self])
        let sharedConfig = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )

        // Seed one event via a setup container, then close it.
        let eventID: UUID
        do {
            let seedContainer = try ModelContainer(for: schema, configurations: [sharedConfig])
            let seedContext = ModelContext(seedContainer)
            let event = EventModel(title: "Original", date: .now, latitude: 0, longitude: 0)
            eventID = event.id
            seedContext.insert(event)
            try seedContext.save()
        }

        // Container A — simulates Device A making an "earlier" offline edit.
        let containerA = try ModelContainer(for: schema, configurations: [sharedConfig])
        let contextA = ModelContext(containerA)
        let fetchA = FetchDescriptor<EventModel>(predicate: #Predicate { $0.id == eventID })
        guard let eventA = try contextA.fetch(fetchA).first else {
            Issue.record("Seed event not found in container A")
            return
        }
        eventA.title = "Device A Edit"

        // Container B — simulates Device B making a "later" offline edit.
        let containerB = try ModelContainer(for: schema, configurations: [sharedConfig])
        let contextB = ModelContext(containerB)
        let fetchB = FetchDescriptor<EventModel>(predicate: #Predicate { $0.id == eventID })
        guard let eventB = try contextB.fetch(fetchB).first else {
            Issue.record("Seed event not found in container B")
            return
        }
        eventB.title = "Device B Edit (later)"

        // Device A syncs first (earlier timestamp).
        try contextA.save()

        // Device B syncs second (later timestamp) — this write must win.
        try contextB.save()

        // Read back through a fresh context to bypass any in-memory cache.
        let verifyContainer = try ModelContainer(for: schema, configurations: [sharedConfig])
        let verifyContext = ModelContext(verifyContainer)
        let fetchVerify = FetchDescriptor<EventModel>(predicate: #Predicate { $0.id == eventID })
        let resolved = try verifyContext.fetch(fetchVerify).first

        #expect(
            resolved?.title == "Device B Edit (later)",
            """
            Last-write-wins contract broken: expected Device B's edit to survive \
            because it saved after Device A, but got '\(resolved?.title ?? "nil")'.
            If NSPersistentCloudKitContainer's merge policy has changed, update the
            conflict resolution comment in PersistenceController.
            """
        )
    }

    /// Targeted regression: the property that broke sync in SHIFT-303 must be
    /// present on the latest `VersionedSchema`'s `TimeBlockModel`.
    @Test func isTransitBlockPropertyIsMirroredInLatestSchema() {
        let snapshotPropsByName = Self.storedPropertyNamesByEntity(
            for: SHIFTMigrationPlan.schemas.last?.models ?? []
        )
        guard let snapshotProps = snapshotPropsByName["TimeBlockModel"] else {
            Issue.record("TimeBlockModel missing from latest VersionedSchema")
            return
        }
        #expect(
            snapshotProps.contains("isTransitBlock"),
            "Live `TimeBlockModel` declares `isTransitBlock` but it is missing from the latest VersionedSchema. CloudKit mirror will silently halt until a SHIFTSchemaV{N+1} snapshot adds this property."
        )
    }
}
