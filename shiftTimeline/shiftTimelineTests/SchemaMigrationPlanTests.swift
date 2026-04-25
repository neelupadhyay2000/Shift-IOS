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

    @Test func latestSchemaVersionIsV6() {
        let latestMajor = SHIFTMigrationPlan.schemas.last?.versionIdentifier.major
        #expect(latestMajor == 6, "Latest schema must be V6 — got \(latestMajor ?? -1)")
    }

    @Test func latestSchemaModelCountMatchesLiveSchema() {
        let latestModels = SHIFTMigrationPlan.schemas.last?.models ?? []
        let liveModelCount = 5 // EventModel, TimeBlockModel, TimelineTrack, VendorModel, ShiftRecord
        #expect(
            latestModels.count == liveModelCount,
            "Latest VersionedSchema must declare all \(liveModelCount) model types"
        )
    }

    // MARK: - V5 → V6 plan continuity

    @Test func planExposesSixSchemasAndFiveStages() {
        #expect(
            SHIFTMigrationPlan.schemas.count == 6,
            "Expected schemas [V1, V2, V3, V4, V5, V6] — got \(SHIFTMigrationPlan.schemas.count)"
        )
        #expect(
            SHIFTMigrationPlan.stages.count == 5,
            "Expected 5 lightweight stages (V1→V2, V2→V3, V3→V4, V4→V5, V5→V6) — got \(SHIFTMigrationPlan.stages.count)"
        )
    }

    @Test func schemasAreOrderedV1ThroughV6() {
        let versions = SHIFTMigrationPlan.schemas.map { $0.versionIdentifier }
        let majors = versions.map { $0.major }
        #expect(majors == [1, 2, 3, 4, 5, 6])
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
}
