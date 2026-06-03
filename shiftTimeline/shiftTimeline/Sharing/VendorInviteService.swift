import CloudKit
import Foundation
import SwiftData
import Models
import Services
import os

/// Errors surfaced while inviting a vendor to a locked CKShare.
enum VendorInviteError: LocalizedError {
    case noContactInfo
    case eventNotSynced
    case participantLookupFailed
    case shareURLMissing

    var errorDescription: String? {
        switch self {
        case .noContactInfo:
            return String(localized: "Add a phone number or email to this vendor before inviting them.")
        case .eventNotSynced:
            return String(localized: "This event hasn't finished syncing to iCloud yet. Try again in a moment.")
        case .participantLookupFailed:
            return String(localized: "That phone/email isn't usable for an iCloud invite. Ask the vendor for the address tied to their Apple ID.")
        case .shareURLMissing:
            return String(localized: "Couldn't generate an invite link. Please try again.")
        }
    }
}

/// Creates and manages **locked, named-participant** CKShares for an event.
///
/// Unlike the old open `UICloudSharingController` flow (anyone with the link
/// could join), this:
///   1. Creates the share with `publicPermission = .none` — only explicitly
///      added participants can accept.
///   2. Adds each invited vendor as a participant **by the exact email/phone**
///      the planner entered (phone preferred). Only that Apple ID can accept,
///      so the accepting identity provably maps back to this vendor (and its
///      block assignments).
///
/// Acceptance is reconciled by `VendorParticipantReconciler`, which stamps
/// `vendor.cloudKitRecordName` so shift notifications route correctly.
///
/// Model-touching entry points (`invite`, `ensureShare`, `existingShare`) are
/// `@MainActor`; the CloudKit I/O wrappers are nonisolated (mirroring
/// `CloudKitDiagnostics`) so their completion-block captures don't cross the
/// main actor.
enum VendorInviteService {

    private static let logger = Logger(subsystem: "com.shift.cloudkit", category: "VendorInviteService")

    private static let container = CKContainer(
        identifier: "iCloud.com.neelsoftwaresolutions.shiftTimeline"
    )

    private static let coreDataZoneID = CKRecordZone.ID(
        zoneName: "com.apple.coredata.cloudkit.zone",
        ownerName: CKCurrentUserDefaultName
    )

    private static let diagnostics = SyncDiagnosticsCenter.shared

    // MARK: - Invite

    /// Ensures the event has a locked share, adds the vendor as a participant by
    /// their phone (preferred) or email, persists `invitedAt`, and returns the
    /// share URL for delivery.
    @MainActor
    @discardableResult
    static func invite(vendor: VendorModel, event: EventModel) async throws -> URL {
        guard let lookup = VendorInviteEligibility.preferredLookup(phone: vendor.phone, email: vendor.email) else {
            throw VendorInviteError.noContactInfo
        }

        diagnostics.record(.shareCreate, "inviteStarted", params: ["event": event.id.uuidString])

        let share = try await ensureShare(for: event)

        let participant = try await fetchParticipant(for: lookup)
        participant.permission = .readOnly
        participant.role = .privateUser
        share.addParticipant(participant)

        try await save([share])

        vendor.invitedAt = .now
        try? PersistenceController.shared.container.mainContext.save()

        guard let url = share.url else { throw VendorInviteError.shareURLMissing }
        diagnostics.record(.shareCreate, "inviteSaved", params: [
            "event": event.id.uuidString,
            "via": lookup.diagnosticChannel,
        ])
        return url
    }

    // MARK: - Share lifecycle

    /// Returns the event's existing CKShare, or creates one (locked to invited
    /// participants only) if none exists yet.
    @MainActor
    static func ensureShare(for event: EventModel) async throws -> CKShare {
        if let urlString = event.shareURL, let url = URL(string: urlString) {
            do {
                return try await fetchShare(url: url)
            } catch {
                // Share was deleted/invalid server-side — fall through and recreate.
                logger.warning("Existing share fetch failed; recreating: \(error.localizedDescription)")
                event.shareURL = nil
            }
        }

        let root = try await findRootRecord(eventID: event.id)
        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = event.title as CKRecordValue
        // Locked: only explicitly added participants may accept.
        share.publicPermission = .none

        let children = await CloudKitShareRepairService.fetchChildRecords(
            rootRecord: root,
            zone: root.recordID.zoneID
        )

        try await save([root] + children + [share])

        event.shareURL = share.url?.absoluteString
        try? PersistenceController.shared.container.mainContext.save()

        diagnostics.record(.shareCreate, "saveSucceeded", params: [
            "event": event.id.uuidString,
            "children": "\(children.count)",
            "locked": "true",
        ])
        return share
    }

    /// Returns the event's existing share without creating one. Used by
    /// `VendorParticipantReconciler` to read participant acceptance.
    @MainActor
    static func existingShare(for event: EventModel) async -> CKShare? {
        guard let urlString = event.shareURL, let url = URL(string: urlString) else { return nil }
        return try? await fetchShare(url: url)
    }

    // MARK: - CloudKit async wrappers

    private static func findRootRecord(eventID: UUID) async throws -> CKRecord {
        let query = CKQuery(recordType: "CD_EventModel", predicate: NSPredicate(value: true))
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let (records, next): ([CKRecord], CKQueryOperation.Cursor?) =
                try await withCheckedThrowingContinuation { continuation in
                    var batch: [CKRecord] = []
                    let op: CKQueryOperation = cursor.map { CKQueryOperation(cursor: $0) }
                        ?? CKQueryOperation(query: query)
                    op.zoneID = coreDataZoneID
                    op.recordMatchedBlock = { _, result in
                        if case .success(let record) = result { batch.append(record) }
                    }
                    op.queryResultBlock = { result in
                        switch result {
                        case .success(let nextCursor):
                            continuation.resume(returning: (batch, nextCursor))
                        case .failure(let error):
                            if let ckError = error as? CKError,
                               ckError.code == .unknownItem || ckError.code == .zoneNotFound {
                                continuation.resume(throwing: VendorInviteError.eventNotSynced)
                            } else {
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                    container.privateCloudDatabase.add(op)
                }

            if let match = records.first(where: { record in
                let candidates: [Any?] = [record["CD_id"], record["id"]]
                return candidates.contains { value in
                    if let uuid = value as? UUID { return uuid == eventID }
                    if let string = value as? String { return string == eventID.uuidString }
                    return false
                }
            }) {
                return match
            }
            cursor = next
        } while cursor != nil

        throw VendorInviteError.eventNotSynced
    }

    private static func fetchShare(url: URL) async throws -> CKShare {
        let metadata: CKShare.Metadata = try await withCheckedThrowingContinuation { continuation in
            let op = CKFetchShareMetadataOperation(shareURLs: [url])
            var found: CKShare.Metadata?
            op.perShareMetadataResultBlock = { _, result in
                if case .success(let meta) = result { found = meta }
            }
            op.fetchShareMetadataResultBlock = { result in
                switch result {
                case .success:
                    if let found {
                        continuation.resume(returning: found)
                    } else {
                        continuation.resume(throwing: VendorInviteError.shareURLMissing)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            container.add(op)
        }
        return metadata.share
    }

    private static func fetchParticipant(for lookup: VendorInviteLookup) async throws -> CKShare.Participant {
        let info: CKUserIdentity.LookupInfo
        switch lookup {
        case .phone(let number):
            info = CKUserIdentity.LookupInfo(phoneNumber: number)
        case .email(let address):
            info = CKUserIdentity.LookupInfo(emailAddress: address)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let op = CKFetchShareParticipantsOperation(userIdentityLookupInfos: [info])
            var resolved: CKShare.Participant?
            op.perShareParticipantResultBlock = { _, result in
                if case .success(let participant) = result { resolved = participant }
            }
            op.fetchShareParticipantsResultBlock = { result in
                switch result {
                case .success:
                    if let resolved {
                        continuation.resume(returning: resolved)
                    } else {
                        continuation.resume(throwing: VendorInviteError.participantLookupFailed)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            container.add(op)
        }
    }

    private static func save(_ records: [CKRecord]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let op = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            op.savePolicy = .changedKeys
            op.qualityOfService = .userInitiated
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success: continuation.resume(returning: ())
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            container.privateCloudDatabase.add(op)
        }
    }
}

private extension VendorInviteLookup {
    var diagnosticChannel: String {
        switch self {
        case .phone: return "phone"
        case .email: return "email"
        }
    }
}
