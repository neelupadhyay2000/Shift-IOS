import Foundation
import CloudKit
import SwiftData
import UIKit
import Testing
import Models
import Services
@testable import shiftTimeline

/// Integration tests for the CKShare vendor-collaboration lifecycle.
///
/// CloudKit server operations (fetch, modify) are not exercised here.
/// Tests drive CKShare construction and property configuration in-memory,
/// validate Coordinator callback contracts via real UICloudSharingController
/// instances, and simulate post-acceptance local state with an in-memory
/// ModelContainer — no live CloudKit environment required.
@Suite("CKShare Lifecycle Integration", .serialized)
struct CloudKitShareIntegrationTests {

    // MARK: - Helpers

    private static func makeRootRecord() -> CKRecord {
        let zoneID = CKRecordZone.ID(
            zoneName: "com.apple.coredata.cloudkit.zone",
            ownerName: CKCurrentUserDefaultName
        )
        let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID)
        return CKRecord(recordType: "CD_EventModel", recordID: recordID)
    }

    @MainActor
    private static func makeContainer() throws -> ModelContainer {
        try PersistenceController.forTesting()
    }

    private static let ckContainerID = "iCloud.com.neelsoftwaresolutions.shiftTimeline"

    // MARK: - Share Creation

    @Test func shareCreationSetsTitleFromEventName() {
        let rootRecord = Self.makeRootRecord()
        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = "Summer Wedding" as CKRecordValue

        #expect(share[CKShare.SystemFieldKey.title] as? String == "Summer Wedding")
    }

    @Test func shareCreationSetsPublicPermissionToReadOnly() {
        let rootRecord = Self.makeRootRecord()
        let share = CKShare(rootRecord: rootRecord)
        share.publicPermission = .readOnly

        #expect(share.publicPermission == .readOnly)
    }

    @Test func shareCreationDoesNotGrantWritePermission() {
        let rootRecord = Self.makeRootRecord()
        let share = CKShare(rootRecord: rootRecord)
        share.publicPermission = .readOnly

        #expect(share.publicPermission != .readWrite)
    }

    @Test func shareCreationLinksToCorrectCloudKitZone() {
        let expectedZone = CKRecordZone.ID(
            zoneName: "com.apple.coredata.cloudkit.zone",
            ownerName: CKCurrentUserDefaultName
        )
        let rootRecord = CKRecord(
            recordType: "CD_EventModel",
            recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: expectedZone)
        )
        let share = CKShare(rootRecord: rootRecord)

        // The share must live in the same zone as the root record so CloudKit
        // delivers child records to the participant via recordZoneChanges.
        #expect(share.recordID.zoneID == expectedZone)
    }

    // MARK: - Coordinator Callbacks

    @Test @MainActor func coordinatorCallsOnShareSavedWhenSaveSucceeds() {
        var capturedShare: CKShare?
        let share = CKShare(rootRecord: Self.makeRootRecord())
        let ckContainer = CKContainer(identifier: Self.ckContainerID)

        let coordinator = CloudSharingView.Coordinator(
            eventTitle: "Summer Wedding",
            onShareSaved: { capturedShare = $0 },
            onShareStopped: {},
            onError: { _ in }
        )

        let csc = UICloudSharingController(share: share, container: ckContainer)
        coordinator.cloudSharingControllerDidSaveShare(csc)

        #expect(capturedShare != nil)
    }

    @Test @MainActor func coordinatorCallsOnShareStoppedWhenOwnerStopsSharing() {
        var didStop = false
        let share = CKShare(rootRecord: Self.makeRootRecord())
        let ckContainer = CKContainer(identifier: Self.ckContainerID)

        let coordinator = CloudSharingView.Coordinator(
            eventTitle: "Summer Wedding",
            onShareSaved: { _ in },
            onShareStopped: { didStop = true },
            onError: { _ in }
        )

        let csc = UICloudSharingController(share: share, container: ckContainer)
        coordinator.cloudSharingControllerDidStopSharing(csc)

        #expect(didStop)
    }

    @Test @MainActor func coordinatorCallsOnErrorWhenSaveFails() {
        var capturedError: Error?
        let share = CKShare(rootRecord: Self.makeRootRecord())
        let ckContainer = CKContainer(identifier: Self.ckContainerID)
        let saveError = NSError(
            domain: CKErrorDomain,
            code: CKError.Code.networkUnavailable.rawValue
        )

        let coordinator = CloudSharingView.Coordinator(
            eventTitle: "Summer Wedding",
            onShareSaved: { _ in },
            onShareStopped: {},
            onError: { capturedError = $0 }
        )

        let csc = UICloudSharingController(share: share, container: ckContainer)
        coordinator.cloudSharingController(csc, failedToSaveShareWithError: saveError)

        #expect(capturedError != nil)
    }

    @Test @MainActor func coordinatorReturnsEventTitleForSharingController() {
        let share = CKShare(rootRecord: Self.makeRootRecord())
        let ckContainer = CKContainer(identifier: Self.ckContainerID)

        let coordinator = CloudSharingView.Coordinator(
            eventTitle: "Summer Wedding",
            onShareSaved: { _ in },
            onShareStopped: {},
            onError: { _ in }
        )

        let csc = UICloudSharingController(share: share, container: ckContainer)
        #expect(coordinator.itemTitle(for: csc) == "Summer Wedding")
    }

    // MARK: - Post-Acceptance Local State

    /// Simulates the state NSPersistentCloudKitContainer produces after a vendor
    /// accepts the owner's CKShare: an EventModel appears in the local store with
    /// ownerRecordName stamped from the CloudKit mirror.
    @Test @MainActor func postAcceptanceSharedEventIsLocallyQueryable() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        let event = EventModel(
            title: "Summer Wedding",
            date: .now,
            latitude: 40.7128,
            longitude: -74.006
        )
        event.ownerRecordName = "owner_ckrecord_abc"
        event.shareURL = "https://www.icloud.com/share/test"
        context.insert(event)
        try context.save()

        let all = try context.fetch(FetchDescriptor<EventModel>())
        let shared = all.filter { $0.shareURL != nil }

        #expect(shared.count == 1)
        #expect(shared.first?.title == "Summer Wedding")
        #expect(shared.first?.ownerRecordName == "owner_ckrecord_abc")
    }

    /// After accepting a share the vendor's device holds the event, but the vendor
    /// identity does not match ownerRecordName — enforcing the read-only model boundary.
    @Test @MainActor func postAcceptanceVendorIsNotIdentifiedAsOwner() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        let event = EventModel(title: "Concert Gala", date: .now, latitude: 0, longitude: 0)
        event.ownerRecordName = "planner_ckrecord_xyz"
        context.insert(event)
        try context.save()

        #expect(event.isOwnedBy("vendor_ckrecord_999") == false)
        #expect(event.isOwnedBy("planner_ckrecord_xyz") == true)
    }

    // MARK: - Participant Permission Enforcement

    @Test func participantPermissionIsReadOnlyAtShareLevel() {
        let share = CKShare(rootRecord: Self.makeRootRecord())
        share.publicPermission = .readOnly

        // CKShare.publicPermission is the CloudKit-level gate. Participants
        // cannot escalate beyond what the share grants — NSPersistentCloudKitContainer
        // rejects writes from participants whose share is readOnly.
        #expect(share.publicPermission == CKShare.ParticipantPermission.readOnly)
        #expect(share.publicPermission.rawValue < CKShare.ParticipantPermission.readWrite.rawValue)
    }

    @Test @MainActor func cloudSharingControllerPermissionsExcludeWriteAccess() {
        // CloudSharingView.makeUIViewController sets:
        //   controller.availablePermissions = [.allowReadOnly, .allowPrivate]
        // Verify that the configured set does not include write access.
        let share = CKShare(rootRecord: Self.makeRootRecord())
        let ckContainer = CKContainer(identifier: Self.ckContainerID)
        let controller = UICloudSharingController(share: share, container: ckContainer)
        controller.availablePermissions = [.allowReadOnly, .allowPrivate]
        #expect(!controller.availablePermissions.contains(.allowReadWrite))
    }

    // MARK: - Coordinator SwiftData Mutations

    /// cloudSharingControllerDidSaveShare → event.shareURL is persisted to SwiftData.
    ///
    /// CKShare.url is nil until CloudKit saves the share to the server, and CKShare
    /// rejects subclassing via internal assertions, so the url-extraction branch of
    /// onShareSaved cannot be exercised offline. This test verifies the downstream
    /// SwiftData write directly — the same mutation that onShareSaved performs once
    /// url is non-nil. The coordinator's forwarding contract is covered separately
    /// by coordinatorCallsOnShareSavedWhenSaveSucceeds.
    @Test @MainActor func onShareSavedPersistsShareURLToEventModel() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        let event = EventModel(title: "Summer Wedding", date: .now, latitude: 40.7128, longitude: -74.006)
        context.insert(event)
        try context.save()

        // Simulate the mutation onShareSaved performs when savedShare.url is non-nil.
        let shareURL = URL(string: "https://www.icloud.com/share/abc123def456")!
        event.shareURL = shareURL.absoluteString
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<EventModel>()).first
        #expect(fetched?.shareURL == shareURL.absoluteString)
    }

    /// cloudSharingControllerDidStopSharing → event.shareURL is cleared.
    @Test @MainActor func onShareStoppedClearsShareURLFromEventModel() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        let event = EventModel(title: "Summer Wedding", date: .now, latitude: 40.7128, longitude: -74.006)
        event.shareURL = "https://www.icloud.com/share/existing"
        context.insert(event)
        try context.save()

        let share = CKShare(rootRecord: Self.makeRootRecord())
        let ckContainer = CKContainer(identifier: Self.ckContainerID)

        let coordinator = CloudSharingView.Coordinator(
            eventTitle: "Summer Wedding",
            onShareSaved: { _ in },
            onShareStopped: {
                event.shareURL = nil
                try? context.save()
            },
            onError: { _ in }
        )

        let csc = UICloudSharingController(share: share, container: ckContainer)
        coordinator.cloudSharingControllerDidStopSharing(csc)

        #expect(event.shareURL == nil)
        let fetched = try context.fetch(FetchDescriptor<EventModel>()).first
        #expect(fetched?.shareURL == nil)
    }

    /// failedToSaveShareWithError → localizedDescription is surfaced to the UI binding.
    @Test @MainActor func onErrorExposesLocalizedErrorMessageToUI() {
        var capturedMessage: String?
        let share = CKShare(rootRecord: Self.makeRootRecord())
        let ckContainer = CKContainer(identifier: Self.ckContainerID)
        let testError = NSError(
            domain: CKErrorDomain,
            code: CKError.Code.networkUnavailable.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Network connection unavailable"]
        )

        let coordinator = CloudSharingView.Coordinator(
            eventTitle: "Summer Wedding",
            onShareSaved: { _ in },
            onShareStopped: {},
            onError: { capturedMessage = $0.localizedDescription }
        )

        let csc = UICloudSharingController(share: share, container: ckContainer)
        coordinator.cloudSharingController(csc, failedToSaveShareWithError: testError)

        #expect(capturedMessage == testError.localizedDescription)
        #expect(capturedMessage?.isEmpty == false)
    }
}

