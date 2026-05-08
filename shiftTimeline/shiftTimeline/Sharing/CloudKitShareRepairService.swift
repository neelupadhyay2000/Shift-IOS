import CloudKit
import Models
import os

/// Sets the CloudKit `parent`-field hierarchy for shared events after timeline mutations.
///
/// `NSPersistentCloudKitContainer` does not set the CloudKit-level `parent` field on child records,
/// so `recordZoneChanges` on the shared DB only returns the root record to participants.
/// This service sets `parent` on tracks, vendors, and blocks via `CKModifyRecordsOperation(.changedKeys)`
/// so the full timeline is visible to vendors. The operation is idempotent.
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
    /// Fire-and-forget after every `modelContext.save()` on a shared event mutation.
    /// No-op when `event.shareURL == nil`.
    static func repairParentFieldsIfShared(for event: EventModel) async {
        guard event.shareURL != nil else { return }

        logger.info("Starting parent-field repair for event \(event.id)")

        do {
            guard let rootRecord = try await findRootRecord(for: event) else {
                logger.warning("Root CKRecord not found for event \(event.id) — repair skipped")
                return
            }
            let children = await fetchChildRecords(
                rootRecord: rootRecord,
                zone: rootRecord.recordID.zoneID
            )
            guard !children.isEmpty else {
            // No child records found — either the event timeline is empty or
            // NSPersistentCloudKitContainer hasn't mirrored them to CloudKit yet.
            // Touch the root record with a heartbeat timestamp so CloudKit still
            // notifies participants that this event was modified.
            rootRecord["SHIFT_repairHeartbeat"] = Date() as CKRecordValue
            let touchOp = CKModifyRecordsOperation(
                recordsToSave: [rootRecord],
                recordIDsToDelete: nil
            )
            touchOp.savePolicy = .changedKeys
            touchOp.qualityOfService = .utility
            container.privateCloudDatabase.add(touchOp)
            logger.info("No children for event \(event.id) — root record touched to notify participants")
            return
            }

            let operation = CKModifyRecordsOperation(
                recordsToSave: children,
                recordIDsToDelete: nil
            )
            // .changedKeys prevents conflict with NSPersistentCloudKitContainer's
            // concurrent writes to other fields on the same records.
            operation.savePolicy = .changedKeys
            operation.qualityOfService = .userInteractive
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    self.logger.info("Parent-field repair complete for event \(event.id) — \(children.count) records updated")
                case .failure(let error):
                    self.logger.error("Parent-field repair failed for event \(event.id): \(error.localizedDescription)")
                }
            }
            container.privateCloudDatabase.add(operation)
        } catch {
            // Non-fatal — share remains valid even if repair fails.
            logger.error("Failed to fetch root record for repair: \(error.localizedDescription)")
        }
    }

    /// Repairs child parent-fields given a known root record ID.
    /// Called from `EventDetailView.resolveShare` (management sheet path).
    static func repairChildParentFields(rootRecordID: CKRecord.ID) async {
        do {
            let rootRecord = try await container.privateCloudDatabase.record(for: rootRecordID)
            let children = await fetchChildRecords(
                rootRecord: rootRecord,
                zone: rootRecordID.zoneID
            )
            guard !children.isEmpty else { return }

            let operation = CKModifyRecordsOperation(
                recordsToSave: children,
                recordIDsToDelete: nil
            )
            operation.savePolicy = .changedKeys
            operation.qualityOfService = .userInteractive
            container.privateCloudDatabase.add(operation)
        } catch {
            // Non-fatal.
        }
    }

    /// Fetches and sets parent fields on all child records of a given root.
    /// `internal` so `EventDetailView.createNewShare` can call it directly.
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

    /// Queries `CD_EventModel` records matching `event.id`.
    /// Checks both `CD_id` (current schema) and `id` (legacy) for forward/backward compatibility.
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
