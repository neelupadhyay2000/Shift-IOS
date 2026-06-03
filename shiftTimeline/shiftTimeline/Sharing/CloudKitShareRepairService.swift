import CloudKit
import Models
import Services
import os

/// Repairs the CloudKit `parent`-field hierarchy for shared events after
/// timeline mutations.
///
/// ## Why this is necessary
///
/// `NSPersistentCloudKitContainer` mirrors SwiftData model relationships
/// using reference fields (`CD_event`, `CD_track`) stored as plain Strings.
/// It does **NOT** set the CloudKit-level `parent` field on those records.
///
/// CloudKit's sharing mechanism — specifically `recordZoneChanges` on the
/// recipient's shared database — only returns records whose `parent` chain
/// leads back to the share's root record. Without `parent` being set, child
/// records (tracks, blocks, vendors) exist in CloudKit's private database but
/// are invisible to vendor devices receiving the `CKDatabaseSubscription`
/// change feed.
///
/// The result is that vendors only see an empty event — no timeline, no blocks
/// — until the planner opens the "Manage Vendor Sharing" sheet, which
/// incidentally runs `refreshChildParentFields` and triggers a CloudKit push.
///
/// ## What this service does
///
/// After every `modelContext.save()` on a shared event, this service:
/// 1. Finds the mirrored CloudKit root record for the event (by UUID).
/// 2. Queries all child records (tracks, vendors, blocks).
/// 3. Writes their `parent` field via `CKModifyRecordsOperation(savePolicy: .changedKeys)`.
/// 4. CloudKit detects the modification and fires the `CKDatabaseSubscription`
///    to all participants → vendor device calls `fetchChanges()` and gets the
///    full updated timeline.
///
/// The operation is **idempotent** — writing the same `parent` value again
/// is a no-op from CloudKit's perspective (`.changedKeys` policy ensures no
/// conflict with `NSPersistentCloudKitContainer`'s concurrent writes).
enum CloudKitShareRepairService {

    private static let logger = Logger(
        subsystem: "com.shift.cloudkit",
        category: "CloudKitShareRepairService"
    )

    private static let container = CKContainer(
        identifier: "iCloud.com.neelsoftwaresolutions.shiftTimeline"
    )

    /// The zone where `NSPersistentCloudKitContainer` mirrors all SwiftData records.
    private static let coreDataZoneID = CKRecordZone.ID(
        zoneName: "com.apple.coredata.cloudkit.zone",
        ownerName: CKCurrentUserDefaultName
    )

    // MARK: - Public API

    /// Repairs the CloudKit parent-field hierarchy for a shared event.
    ///
    /// Call this fire-and-forget (inside a `Task { }`) after every
    /// `modelContext.save()` on a mutation to a shared event.
    /// The method is a no-op when `event.shareURL == nil`.
    ///
    /// - Parameter event: The event whose child records need `parent` set.
    static func repairParentFieldsIfShared(for event: EventModel) async {
        guard event.shareURL != nil else {
            SyncDiagnosticsCenter.shared.record(
                .parentRepair,
                "skipped",
                params: ["event": event.id.uuidString, "reason": "notShared"]
            )
            return
        }

        logger.info("Starting parent-field repair for event \(event.id)")
        SyncDiagnosticsCenter.shared.record(.parentRepair, "started", params: ["event": event.id.uuidString])

        do {
            guard let rootRecord = try await findRootRecord(for: event) else {
                logger.warning("Root CKRecord not found for event \(event.id) — repair skipped")
                SyncDiagnosticsCenter.shared.record(
                    .parentRepair,
                    "noRootRecord",
                    params: ["event": event.id.uuidString],
                    severity: .warning
                )
                return
            }
            let children = await fetchChildRecords(
                rootRecord: rootRecord,
                zone: rootRecord.recordID.zoneID
            )

            // CRITICAL: always stamp a fresh, monotonically-changing heartbeat on
            // the ROOT record. CloudKit dedupes identical field writes server-side,
            // so re-writing already-correct `parent` references on the children is a
            // no-op — the shared zone's change tag never moves, the vendor's
            // `databaseChanges` returns 0 forever, and they never re-fetch. A new
            // `Date()` every time guarantees a real zone change on every edit, which
            // fires the vendor's CKDatabaseSubscription so they pull the latest data.
            rootRecord["SHIFT_repairHeartbeat"] = Date() as CKRecordValue

            let recordsToSave = [rootRecord] + children
            let operation = CKModifyRecordsOperation(
                recordsToSave: recordsToSave,
                recordIDsToDelete: nil
            )
            // .changedKeys prevents conflict with NSPersistentCloudKitContainer's
            // concurrent writes to other fields on the same records — we only
            // write the heartbeat (root) and the parent refs (children).
            operation.savePolicy = .changedKeys
            operation.qualityOfService = .userInitiated
            let childCount = children.count
            let eventID = event.id.uuidString
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    self.logger.info("Parent-field repair complete for event \(event.id) — \(childCount) children + heartbeat")
                    SyncDiagnosticsCenter.shared.record(
                        .parentRepair,
                        "wroteChildren",
                        params: ["event": eventID, "children": "\(childCount)", "heartbeat": "true"]
                    )
                case .failure(let error):
                    self.logger.error("Parent-field repair failed for event \(event.id): \(error.localizedDescription)")
                    SyncDiagnosticsCenter.shared.record(
                        .parentRepair,
                        "writeFailed",
                        params: ["event": eventID, "error": error.localizedDescription],
                        severity: .error
                    )
                }
            }
            container.privateCloudDatabase.add(operation)
        } catch {
            // Non-fatal — the share remains valid even if repair fails.
            // The planner can still open the management sheet as a fallback.
            logger.error("Failed to fetch root record for repair: \(error.localizedDescription)")
            SyncDiagnosticsCenter.shared.record(
                .parentRepair,
                "rootFetchFailed",
                params: ["event": event.id.uuidString, "error": error.localizedDescription],
                severity: .error
            )
        }
    }

    /// Repairs the CloudKit parent-field hierarchy given a known root record ID.
    ///
    /// Called by `EventDetailView.resolveShare` (management sheet path) and
    /// is the same idempotent repair, just skipping the root-record lookup.
    static func repairChildParentFields(rootRecordID: CKRecord.ID) async {
        do {
            let rootRecord = try await container.privateCloudDatabase.record(for: rootRecordID)
            let children = await fetchChildRecords(
                rootRecord: rootRecord,
                zone: rootRecordID.zoneID
            )

            // Always heartbeat the root (see repairParentFieldsIfShared) so this
            // path reliably bumps the shared zone even when parents are unchanged.
            rootRecord["SHIFT_repairHeartbeat"] = Date() as CKRecordValue

            let operation = CKModifyRecordsOperation(
                recordsToSave: [rootRecord] + children,
                recordIDsToDelete: nil
            )
            operation.savePolicy = .changedKeys
            operation.qualityOfService = .userInitiated
            container.privateCloudDatabase.add(operation)
        } catch {
            // Non-fatal.
        }
    }

    /// Fetches and sets parent fields on all child records of a given root.
    ///
    /// Exposed `internal` so `EventDetailView.createNewShare` can call it when
    /// constructing the initial share payload (where it already has the root record).
    static func fetchChildRecords(
        rootRecord: CKRecord,
        zone: CKRecordZone.ID
    ) async -> [CKRecord] {
        let eventRecordName = rootRecord.recordID.recordName
        var children: [CKRecord] = []

        let tracks = await queryRecords(
            type: "CD_TimelineTrack",
            predicate: NSPredicate(format: "CD_event == %@", eventRecordName),
            zone: zone
        )
        for track in tracks {
            // .none action — .deleteSelf triggers an NSAssertionHandler abort in iOS 26.
            track.parent = CKRecord.Reference(recordID: rootRecord.recordID, action: .none)
        }
        children.append(contentsOf: tracks)

        let vendors = await queryRecords(
            type: "CD_VendorModel",
            predicate: NSPredicate(format: "CD_event == %@", eventRecordName),
            zone: zone
        )
        for vendor in vendors {
            vendor.parent = CKRecord.Reference(recordID: rootRecord.recordID, action: .none)
        }
        children.append(contentsOf: vendors)

        for track in tracks {
            let blocks = await queryRecords(
                type: "CD_TimeBlockModel",
                predicate: NSPredicate(format: "CD_track == %@", track.recordID.recordName),
                zone: zone
            )
            for block in blocks {
                block.parent = CKRecord.Reference(recordID: track.recordID, action: .none)
            }
            children.append(contentsOf: blocks)
        }

        return children
    }

    // MARK: - Private Helpers

    /// Queries `CD_EventModel` records to find the one matching `event.id`.
    ///
    /// `NSPersistentCloudKitContainer` uses opaque record names — the UUID field
    /// is stored as either `CD_id` (current schema) or `id` (legacy). Both are
    /// checked for forward and backward compatibility.
    private static func findRootRecord(for event: EventModel) async throws -> CKRecord? {
        let query = CKQuery(
            recordType: "CD_EventModel",
            predicate: NSPredicate(value: true)
        )
        var found: CKRecord?
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let (pageRecords, nextCursor): ([CKRecord], CKQueryOperation.Cursor?) =
                try await withCheckedThrowingContinuation { continuation in
                    var batch: [CKRecord] = []
                    let op: CKQueryOperation = cursor.map {
                        CKQueryOperation(cursor: $0)
                    } ?? CKQueryOperation(query: query)
                    op.zoneID = coreDataZoneID
                    op.recordMatchedBlock = { _, result in
                        if case .success(let record) = result { batch.append(record) }
                    }
                    op.queryResultBlock = { result in
                        switch result {
                        case .success(let next):
                            continuation.resume(returning: (batch, next))
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }
                    container.privateCloudDatabase.add(op)
                }

            found = pageRecords.first { record in
                let candidates: [Any?] = [record["CD_id"], record["id"]]
                return candidates.contains { value in
                    if let uuid = value as? UUID { return uuid == event.id }
                    if let string = value as? String { return string == event.id.uuidString }
                    return false
                }
            }
            cursor = nextCursor
        } while found == nil && cursor != nil

        return found
    }

    /// Pages through a CloudKit query and returns all matching records.
    /// On query failure, returns whatever records were fetched before the error.
    private static func queryRecords(
        type: String,
        predicate: NSPredicate,
        zone: CKRecordZone.ID
    ) async -> [CKRecord] {
        var all: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let (pageRecords, nextCursor): ([CKRecord], CKQueryOperation.Cursor?) =
                await withCheckedContinuation { continuation in
                    var batch: [CKRecord] = []
                    let op: CKQueryOperation = cursor.map {
                        CKQueryOperation(cursor: $0)
                    } ?? CKQueryOperation(query: CKQuery(recordType: type, predicate: predicate))
                    op.zoneID = zone
                    op.recordMatchedBlock = { _, result in
                        if case .success(let record) = result { batch.append(record) }
                    }
                    op.queryResultBlock = { result in
                        switch result {
                        case .success(let next):
                            continuation.resume(returning: (batch, next))
                        case .failure:
                            continuation.resume(returning: (batch, nil))
                        }
                    }
                    container.privateCloudDatabase.add(op)
                }

            all.append(contentsOf: pageRecords)
            cursor = nextCursor
        } while cursor != nil

        return all
    }
}
