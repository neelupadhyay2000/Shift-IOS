import CloudKit
import Models
import Services
import os

/// Read-only CloudKit inspection helpers for the diagnostics screen.
///
/// Unlike `CloudKitShareRepairService`, this type **never mutates** CloudKit
/// records — it reports the server's actual state (does the CKShare exist? do
/// child records already carry a `parent`? is the vendor's shared zone
/// populated?) so we can localize where the share/sync funnel breaks.
///
/// Every probe also records a `DiagnosticEvent` into `SyncDiagnosticsCenter`
/// so results appear in the in-app log and the TelemetryDeck bridge.
enum CloudKitDiagnostics {

    private static let logger = Logger(subsystem: "com.shift.diagnostics", category: "CloudKitDiagnostics")

    private static let container = CKContainer(
        identifier: "iCloud.com.neelsoftwaresolutions.shiftTimeline"
    )

    /// The zone where `NSPersistentCloudKitContainer` mirrors all private SwiftData records.
    private static let coreDataZoneID = CKRecordZone.ID(
        zoneName: "com.apple.coredata.cloudkit.zone",
        ownerName: CKCurrentUserDefaultName
    )

    private static let diagnostics = SyncDiagnosticsCenter.shared

    // MARK: - Account status

    /// Reports the iCloud account status. A status other than `.available` is
    /// the single most common reason sharing silently does nothing (vendor not
    /// signed in, or account restricted).
    @discardableResult
    static func checkAccountStatus() async -> CKAccountStatus {
        do {
            let status = try await container.accountStatus()
            diagnostics.record(
                .account,
                "status",
                params: ["value": status.diagnosticName],
                severity: status == .available ? .info : .warning
            )
            return status
        } catch {
            diagnostics.record(
                .account,
                "statusError",
                params: ["error": error.localizedDescription],
                severity: .error
            )
            return .couldNotDetermine
        }
    }

    // MARK: - Planner side: inspect a share

    /// Inspects the CKShare for an event: whether the mirrored root record and
    /// share exist, participant acceptance breakdown, and how many child records
    /// already carry a `parent` reference (the field vendors need to see them).
    ///
    /// Takes a `UUID` (Sendable) rather than the `EventModel` so it can be
    /// driven from a `@Sendable` Task closure without crossing isolation with a
    /// non-Sendable SwiftData model.
    static func inspectShare(eventID id: UUID) async {
        let eventID = id.uuidString
        diagnostics.record(.shareCreate, "inspectStarted", params: ["event": eventID])

        guard let root = await findRootRecord(forEventID: id) else {
            diagnostics.record(
                .shareCreate,
                "inspectNoRootRecord",
                params: ["event": eventID],
                severity: .warning
            )
            return
        }

        // Child parent-field coverage — the crux of why vendors see empty events.
        let (childTotal, parented) = await childParentCoverage(rootRecord: root)
        diagnostics.record(
            .parentRepair,
            "coverage",
            params: [
                "event": eventID,
                "children": "\(childTotal)",
                "parented": "\(parented)",
            ],
            severity: (childTotal > 0 && parented < childTotal) ? .warning : .info
        )

        // CKShare presence + participants.
        guard let shareRef = root.share else {
            diagnostics.record(
                .shareCreate,
                "inspectNoShareReference",
                params: ["event": eventID],
                severity: .warning
            )
            return
        }

        do {
            let shareRecord = try await container.privateCloudDatabase.record(for: shareRef.recordID)
            guard let share = shareRecord as? CKShare else {
                diagnostics.record(.shareCreate, "inspectShareNotCKShare", params: ["event": eventID], severity: .error)
                return
            }
            var accepted = 0
            var pending = 0
            var other = 0
            for participant in share.participants where participant.role != .owner {
                switch participant.acceptanceStatus {
                case .accepted: accepted += 1
                case .pending: pending += 1
                default: other += 1
                }
            }
            diagnostics.record(
                .shareCreate,
                "inspectShareFound",
                params: [
                    "event": eventID,
                    "participants": "\(share.participants.count)",
                    "accepted": "\(accepted)",
                    "pending": "\(pending)",
                    "other": "\(other)",
                    "publicPermission": share.publicPermission.diagnosticName,
                ]
            )
        } catch {
            diagnostics.record(
                .shareCreate,
                "inspectShareFetchFailed",
                params: ["event": eventID, "error": error.localizedDescription],
                severity: .error
            )
        }
    }

    // MARK: - Vendor side: shared-zone inventory

    /// Inventories the shared database: how many zones are visible and how many
    /// records of each type are actually present. On a vendor device that
    /// "sees nothing," this shows whether the records reached the device at all.
    static func inventorySharedZones() async {
        do {
            let zones = try await container.sharedCloudDatabase.allRecordZones()
            diagnostics.record(.fetch, "sharedZones", params: ["count": "\(zones.count)"])

            for zone in zones {
                var counts: [String: Int] = [:]
                for type in ["CD_EventModel", "CD_TimelineTrack", "CD_TimeBlockModel", "CD_VendorModel"] {
                    counts[type] = await count(
                        type: type,
                        in: container.sharedCloudDatabase,
                        zone: zone.zoneID
                    )
                }
                diagnostics.record(
                    .fetch,
                    "sharedZoneInventory",
                    params: [
                        "zone": zone.zoneID.zoneName,
                        "owner": zone.zoneID.ownerName,
                        "events": "\(counts["CD_EventModel"] ?? 0)",
                        "tracks": "\(counts["CD_TimelineTrack"] ?? 0)",
                        "blocks": "\(counts["CD_TimeBlockModel"] ?? 0)",
                        "vendors": "\(counts["CD_VendorModel"] ?? 0)",
                    ]
                )
            }
        } catch {
            diagnostics.record(
                .fetch,
                "sharedZonesError",
                params: ["error": error.localizedDescription],
                severity: .error
            )
        }
    }

    // MARK: - Private query helpers (read-only)

    /// Counts how many child records (tracks, blocks, vendors) of the event's
    /// root already carry a non-nil `parent` reference.
    private static func childParentCoverage(rootRecord: CKRecord) async -> (total: Int, parented: Int) {
        let eventRecordName = rootRecord.recordID.recordName
        var total = 0
        var parented = 0

        let tracks = await query(
            type: "CD_TimelineTrack",
            predicate: NSPredicate(format: "CD_event == %@", eventRecordName),
            in: container.privateCloudDatabase,
            zone: rootRecord.recordID.zoneID
        )
        for track in tracks {
            total += 1
            if track.parent != nil { parented += 1 }
            let blocks = await query(
                type: "CD_TimeBlockModel",
                predicate: NSPredicate(format: "CD_track == %@", track.recordID.recordName),
                in: container.privateCloudDatabase,
                zone: rootRecord.recordID.zoneID
            )
            for block in blocks {
                total += 1
                if block.parent != nil { parented += 1 }
            }
        }

        let vendors = await query(
            type: "CD_VendorModel",
            predicate: NSPredicate(format: "CD_event == %@", eventRecordName),
            in: container.privateCloudDatabase,
            zone: rootRecord.recordID.zoneID
        )
        for vendor in vendors {
            total += 1
            if vendor.parent != nil { parented += 1 }
        }

        return (total, parented)
    }

    /// Finds the mirrored `CD_EventModel` root record matching the event UUID.
    /// Mirrors `CloudKitShareRepairService`'s lookup (checks `CD_id` and legacy `id`).
    private static func findRootRecord(forEventID eventID: UUID) async -> CKRecord? {
        let records = await query(
            type: "CD_EventModel",
            predicate: NSPredicate(value: true),
            in: container.privateCloudDatabase,
            zone: coreDataZoneID
        )
        return records.first { record in
            let candidates: [Any?] = [record["CD_id"], record["id"]]
            return candidates.contains { value in
                if let uuid = value as? UUID { return uuid == eventID }
                if let string = value as? String { return string == eventID.uuidString }
                return false
            }
        }
    }

    private static func count(
        type: String,
        in database: CKDatabase,
        zone: CKRecordZone.ID
    ) async -> Int {
        await query(type: type, predicate: NSPredicate(value: true), in: database, zone: zone).count
    }

    /// Pages through a read-only CloudKit query. On failure, returns whatever
    /// was fetched before the error (diagnostics should degrade, not throw).
    private static func query(
        type: String,
        predicate: NSPredicate,
        in database: CKDatabase,
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
                    database.add(op)
                }

            all.append(contentsOf: pageRecords)
            cursor = nextCursor
        } while cursor != nil

        return all
    }
}

// MARK: - Diagnostic names

private extension CKAccountStatus {
    var diagnosticName: String {
        switch self {
        case .available: return "available"
        case .noAccount: return "noAccount"
        case .restricted: return "restricted"
        case .couldNotDetermine: return "couldNotDetermine"
        case .temporarilyUnavailable: return "temporarilyUnavailable"
        @unknown default: return "unknown"
        }
    }
}

private extension CKShare.ParticipantPermission {
    var diagnosticName: String {
        switch self {
        case .none: return "none"
        case .readOnly: return "readOnly"
        case .readWrite: return "readWrite"
        case .unknown: return "unknown"
        @unknown default: return "unknown"
        }
    }
}
