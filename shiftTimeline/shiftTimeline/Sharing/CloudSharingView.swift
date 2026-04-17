import SwiftUI
import UIKit
import CloudKit

/// A SwiftUI wrapper around `UICloudSharingController`.
///
/// Uses `init(preparationHandler:)` when creating a new share, and
/// `init(share:container:)` when managing an existing one.
/// The `availablePermissions` are locked to `.allowReadOnly` + `.allowPrivate`
/// so vendors can never gain write access.
struct CloudSharingView: UIViewControllerRepresentable {

    let container: CKContainer
    let eventTitle: String

    /// `nil` for a new share, non-nil for managing an existing share.
    let existingShare: CKShare?

    /// Called after CloudKit saves a new share. Provides the share URL string
    /// so the caller can persist it on the `EventModel`.
    let onShareCreated: (String) -> Void

    /// Called when the user stops sharing entirely.
    let onShareStopped: () -> Void

    /// Called when saving the share fails.
    let onError: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            eventTitle: eventTitle,
            onShareCreated: onShareCreated,
            onShareStopped: onShareStopped,
            onError: onError
        )
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller: UICloudSharingController

        if let existingShare {
            // Manage an existing share (add/remove participants).
            controller = UICloudSharingController(share: existingShare, container: container)
        } else {
            // Create a new share via the preparation handler.
            controller = UICloudSharingController { sharingController, completion in
                let share = CKShare(recordZoneID: .default)
                share[CKShare.SystemFieldKey.title] = eventTitle as CKRecordValue
                share.publicPermission = .readOnly

                let operation = CKModifyRecordsOperation(recordsToSave: [share], recordIDsToDelete: nil)
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        completion(share, self.container, nil)
                    case .failure(let error):
                        completion(nil, nil, error)
                    }
                }
                self.container.privateCloudDatabase.add(operation)
            }
        }

        controller.availablePermissions = [.allowReadOnly, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    // MARK: - Coordinator

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {

        private let eventTitle: String
        private let onShareCreated: (String) -> Void
        private let onShareStopped: () -> Void
        private let onError: (Error) -> Void

        init(
            eventTitle: String,
            onShareCreated: @escaping (String) -> Void,
            onShareStopped: @escaping () -> Void,
            onError: @escaping (Error) -> Void
        ) {
            self.eventTitle = eventTitle
            self.onShareCreated = onShareCreated
            self.onShareStopped = onShareStopped
            self.onError = onError
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            guard let url = csc.share?.url else { return }
            onShareCreated(url.absoluteString)
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onShareStopped()
        }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            onError(error)
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            eventTitle
        }
    }
}
