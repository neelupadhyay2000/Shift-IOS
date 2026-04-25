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

    @Test func latestSchemaVersionIsV4() {
        let latest = SHIFTMigrationPlan.schemas.last
        #expect(latest == SHIFTSchemaV4.self)
    }

    @Test func latestSchemaModelCountMatchesLiveSchema() {
        let latestModels = SHIFTMigrationPlan.schemas.last?.models ?? []
        let liveModelCount = 5 // EventModel, TimeBlockModel, TimelineTrack, VendorModel, ShiftRecord
        #expect(
            latestModels.count == liveModelCount,
            "Latest VersionedSchema must declare all \(liveModelCount) model types"
        )
    }
}
