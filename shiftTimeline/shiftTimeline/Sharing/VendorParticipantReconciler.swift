import CloudKit
import Foundation
import SwiftData
import Models
import Services
import os

/// The **claim-on-accept** step: reads the event's CKShare participants and
/// stamps `vendor.cloudKitRecordName` on the matching `VendorModel` (by the
/// email/phone the vendor was invited with).
///
/// Once stamped on the planner's device, the value syncs to the vendor's device
/// where `EventModel.vendorForUser(currentUserRecordName)` matches it — which is
/// what lets `VendorShiftLocalNotifier` route a shift notification to the right
/// vendor.
///
/// Run on the owner's device after inviting, on app-active, and after a share is
/// accepted. Pure matching lives in `VendorParticipantMatcher` (unit-tested).
@MainActor
enum VendorParticipantReconciler {

    private static let logger = Logger(subsystem: "com.shift.cloudkit", category: "VendorParticipantReconciler")
    private static let diagnostics = SyncDiagnosticsCenter.shared

    /// Reconciles every owned, shared event in the store.
    static func reconcileAll() async {
        let context = PersistenceController.shared.container.mainContext
        let descriptor = FetchDescriptor<EventModel>()
        guard let events = try? context.fetch(descriptor) else { return }
        let identity = CloudKitIdentity.shared.currentUserRecordName
        for event in events where event.shareURL != nil && event.isOwnedBy(identity) {
            await reconcile(event: event)
        }
    }

    /// Reconciles a single event's vendors against its CKShare participants.
    static func reconcile(event: EventModel) async {
        guard let share = await VendorInviteService.existingShare(for: event) else { return }

        let vendors = event.vendors ?? []
        guard !vendors.isEmpty else { return }

        let vendorRefs = vendors.map { VendorRef(id: $0.id, email: $0.email, phone: $0.phone) }
        let participants = share.participants
            .filter { $0.role != .owner }
            .map { participant in
                ParticipantInfo(
                    recordName: participant.userIdentity.userRecordID?.recordName,
                    email: participant.userIdentity.lookupInfo?.emailAddress,
                    phone: participant.userIdentity.lookupInfo?.phoneNumber
                )
            }

        let matches = VendorParticipantMatcher.match(participants: participants, vendors: vendorRefs)

        var changed = false
        for match in matches {
            guard let vendor = vendors.first(where: { $0.id == match.vendorID }) else { continue }
            if vendor.cloudKitRecordName != match.recordName {
                vendor.cloudKitRecordName = match.recordName
                changed = true
                diagnostics.record(.shareAccept, "vendorLinked", params: ["vendor": vendor.id.uuidString])
            }
        }

        if changed {
            try? PersistenceController.shared.container.mainContext.save()
            logger.info("Linked \(matches.count) vendor(s) for event \(event.id)")
        }
    }
}
