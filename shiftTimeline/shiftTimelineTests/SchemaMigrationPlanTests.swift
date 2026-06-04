import Foundation
import Models
import Services
import SwiftData
import Testing

/// Guards against the exact failure mode that broke CloudKit sync:
/// `VersionedSchema` types referencing live model types produce identical
/// checksums, causing `MigrationStage.lightweight` to throw an
/// `NSException` at container init time.
///
/// If any of these tests fail, the migration plan is broken and CloudKit
/// sync will silently degrade in production.
@Suite("Schema Migration Plan Integrity")
struct SchemaMigrationPlanTests {

    // MARK: - Version Uniqueness

    @Test func allSchemaVersionsAreUnique() {
        let versions = SHIFTMigrationPlan.schemas.map {
            $0.versionIdentifier
        }
        let unique = Set(versions.map { "\($0.major).\($0.minor).\($0.patch)" })
        #expect(
            unique.count == versions.count,
            "Duplicate version identifiers found — each VersionedSchema must have a unique version"
        )
    }

    @Test func stageCountMatchesSchemaTransitions() {
        let schemaCount = SHIFTMigrationPlan.schemas.count
        let stageCount = SHIFTMigrationPlan.stages.count
        #expect(
            stageCount == schemaCount - 1,
            "Expected \(schemaCount - 1) migration stages for \(schemaCount) schemas, got \(stageCount)"
        )
    }

    // MARK: - Container Creation (catches NSException from bad checksums)

    @Test func modelContainerWithMigrationPlanSucceeds() throws {
        let schema = PersistenceController.schema
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        let container = try ModelContainer(
            for: schema,
            migrationPlan: SHIFTMigrationPlan.self,
            configurations: [config]
        )
        #expect(container.schema.entities.isEmpty == false)
    }

    // MARK: - Latest Schema Matches Live Models

    @Test func latestSchemaVersionIsV12() {
        let latestMajor = SHIFTMigrationPlan.schemas.last?.versionIdentifier.major
        #expect(latestMajor == 12, "Latest schema must be V12 — got \(latestMajor ?? -1)")
    }

    @Test func latestSchemaModelCountMatchesLiveSchema() {
        let latestModels = SHIFTMigrationPlan.schemas.last?.models ?? []
        let liveModelCount = 6 // EventModel, TimeBlockModel, TimelineTrack, VendorModel, ShiftRecord, OutboxEntry
        #expect(
            latestModels.count == liveModelCount,
            "Latest Versioned Schema must declare all \(liveModelCount) model types"
        )
    }

    // MARK: - V11 → V12 plan continuity

    @Test func planExposesTwelveSchemasAndElevenStages() {
        #expect(
            SHIFTMigrationPlan.schemas.count == 12,
            "Expected schemas [V1 … V12] — got \(SHIFTMigrationPlan.schemas.count)"
        )
        #expect(
            SHIFTMigrationPlan.stages.count == 11,
            "Expected 11 lightweight stages (V1→V2 … V11→V12) — got \(SHIFTMigrationPlan.stages.count)"
        )
    }

    @Test func schemasAreOrderedV1ThroughV12() {
        let versions = SHIFTMigrationPlan.schemas.map { $0.versionIdentifier }
        let majors = versions.map { $0.major }
        #expect(majors == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
    }

    /// Lightweight V8 → V9 migration must default `VendorModel.invitedAt` to
    /// `nil` for legacy rows and round-trip an explicit value.
    @Test @MainActor func freshContainerWithV9PlanRoundTripsInvitedAt() throws {
        let schema = PersistenceController.schema
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: SHIFTMigrationPlan.self,
            configurations: [config]
        )
        let context = container.mainContext

        let vendor = VendorModel(name: "Alice", role: .photographer)
        context.insert(vendor)
        try context.save()

        #expect(vendor.invitedAt == nil)

        let stamp = Date(timeIntervalSince1970: 1_770_000_000)
        vendor.invitedAt = stamp
        try context.save()

        #expect(vendor.invitedAt == stamp)
    }

    /// Lightweight V10 → V11 migration drops CloudKit-only fields. Verify that
    /// the retained Supabase cache fields (`invitedAt`, `pendingShiftDelta`,
    /// `hasAcknowledgedLatestShift`) and the event analytics timestamps
    /// (`wentLiveAt`, `completedAt`) still round-trip correctly.
    @Test @MainActor func freshContainerWithV11PlanRoundTripsRetainedCacheFields() throws {
        let schema = PersistenceController.schema
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: SHIFTMigrationPlan.self,
            configurations: [config]
        )
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let vendor = VendorModel(name: "Alice", role: .photographer)
        vendor.event = event
        context.insert(vendor)

        try context.save()

        // Defaults
        #expect(vendor.invitedAt == nil)
        #expect(vendor.pendingShiftDelta == nil)
        #expect(vendor.hasAcknowledgedLatestShift == false)
        #expect(event.wentLiveAt == nil)
        #expect(event.completedAt == nil)

        // Explicit round-trip
        let inviteStamp = Date(timeIntervalSince1970: 1_790_000_000)
        let liveStamp = Date(timeIntervalSince1970: 1_790_001_000)
        let doneStamp = Date(timeIntervalSince1970: 1_790_005_000)
        vendor.invitedAt = inviteStamp
        vendor.pendingShiftDelta = 300
        vendor.hasAcknowledgedLatestShift = true
        event.wentLiveAt = liveStamp
        event.completedAt = doneStamp
        try context.save()

        #expect(vendor.invitedAt == inviteStamp)
        #expect(vendor.pendingShiftDelta == 300)
        #expect(vendor.hasAcknowledgedLatestShift == true)
        #expect(event.wentLiveAt == liveStamp)
        #expect(event.completedAt == doneStamp)
    }

    /// Lightweight V11 → V12 migration adds `OutboxEntry`. Verify that the
    /// new table is queryable and that all fields default correctly and
    /// round-trip an explicit insert.
    @Test @MainActor func freshContainerWithV12PlanRoundTripsOutboxEntry() throws {
        let schema = PersistenceController.schema
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: SHIFTMigrationPlan.self,
            configurations: [config]
        )
        let context = container.mainContext

        // Table starts empty
        let initial = try context.fetch(FetchDescriptor<OutboxEntry>())
        #expect(initial.isEmpty)

        // Insert and persist
        let rowID = UUID()
        let entry = OutboxEntry(tableName: "events", rowID: rowID, operation: "update")
        context.insert(entry)
        try context.save()

        // Defaults
        #expect(entry.attempts == 0)
        #expect(entry.payload == nil)

        // Explicit round-trip
        let payload = try #require("{\"title\":\"Wedding\"}".data(using: .utf8))
        entry.attempts = 2
        entry.payload = payload
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<OutboxEntry>())
        let saved = try #require(fetched.first)
        #expect(saved.tableName == "events")
        #expect(saved.rowID == rowID)
        #expect(saved.operation == "update")
        #expect(saved.attempts == 2)
        #expect(saved.payload == payload)
    }

    /// Lightweight V4 → V5 migration must default `TimeBlockModel.isTransitBlock`
    /// to `false` for legacy rows and preserve all V4 properties.
    @Test @MainActor func freshContainerWithV5PlanInsertsAndReadsIsTransitBlock() throws {
        let schema = PersistenceController.schema
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: SHIFTMigrationPlan.self,
            configurations: [config]
        )
        let context = container.mainContext

        let block = TimeBlockModel(
            title: "Ceremony",
            scheduledStart: .now,
            duration: 1800
        )
        context.insert(block)
        try context.save()

        // Default value must round-trip to `false` (the lightweight migration default).
        #expect(block.isTransitBlock == false)

        // Explicit set must round-trip too.
        block.isTransitBlock = true
        try context.save()
        #expect(block.isTransitBlock == true)
    }

    /// Lightweight V5 → V6 migration must default the new fields
    /// (`TimeBlockModel.completedTime`, `EventModel.postEventReportData`)
    /// to `nil` for legacy rows and round-trip explicit values.
    @Test @MainActor func freshContainerWithV6PlanRoundTripsCompletedTimeAndReportPayload() throws {
        let schema = PersistenceController.schema
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: SHIFTMigrationPlan.self,
            configurations: [config]
        )
        let context = container.mainContext

        let block = TimeBlockModel(
            title: "Ceremony",
            scheduledStart: .now,
            duration: 1800
        )
        context.insert(block)

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)
        try context.save()

        // Defaults round-trip to `nil`.
        #expect(block.completedTime == nil)
        #expect(event.postEventReportData == nil)
        #expect(event.postEventReport == nil)

        // Explicit values round-trip.
        let stamp = Date(timeIntervalSince1970: 1_750_000_000)
        block.completedTime = stamp
        event.postEventReport = PostEventReport(
            entries: [],
            totalDriftMinutes: 0,
            totalShiftCount: 0,
            generatedAt: stamp
        )
        try context.save()

        #expect(block.completedTime == stamp)
        #expect(event.postEventReport?.generatedAt == stamp)
    }

    /// Lightweight V6 → V7 migration must default the new fields
    /// (`EventModel.wentLiveAt`, `EventModel.completedAt`) to `nil` for
    /// legacy rows and round-trip explicit values.
    @Test @MainActor func freshContainerWithV7PlanRoundTripsSessionTimestamps() throws {
        let schema = PersistenceController.schema
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: SHIFTMigrationPlan.self,
            configurations: [config]
        )
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)
        try context.save()

        #expect(event.wentLiveAt == nil)
        #expect(event.completedAt == nil)

        let liveStamp = Date(timeIntervalSince1970: 1_760_000_000)
        let doneStamp = Date(timeIntervalSince1970: 1_760_004_000)
        event.wentLiveAt = liveStamp
        event.completedAt = doneStamp
        try context.save()

        #expect(event.wentLiveAt == liveStamp)
        #expect(event.completedAt == doneStamp)
    }
}
