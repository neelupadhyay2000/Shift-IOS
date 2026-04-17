#if canImport(UIKit)
import SwiftUI
import UIKit
import CloudKit

/// A SwiftUI wrapper around `UICloudSharingController`.
///
/// Always uses `init(share:container:)` — the non-deprecated path.
/// The caller is responsible for creating and saving the `CKShare` before
/// presenting this view. `availablePermissions` are locked to read-only
/// so vendors can never gain write access.
struct CloudSharingView: UIViewControllerRepresentable {

    let share: CKShare
    let container: CKContainer
    let eventTitle: String

    /// Called after CloudKit saves share changes (new participants, etc.).
    let onShareSaved: (CKShare) -> Void

    /// Called when the user stops sharing entirely.
    let onShareStopped: () -> Void

    /// Called when saving the share fails.
    let onError: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            eventTitle: eventTitle,
            onShareSaved: onShareSaved,
            onShareStopped: onShareStopped,
            onError: onError
        )
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadOnly, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    // MARK: - Coordinator

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {

        private let eventTitle: String
        private let onShareSaved: (CKShare) -> Void
        private let onShareStopped: () -> Void
        private let onError: (Error) -> Void

        init(
            eventTitle: String,
            onShareSaved: @escaping (CKShare) -> Void,
            onShareStopped: @escaping () -> Void,
            onError: @escaping (Error) -> Void
        ) {
            self.eventTitle = eventTitle
            self.onShareSaved = onShareSaved
            self.onShareStopped = onShareStopped
            self.onError = onError  
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            guard let share = csc.share else { return }
            onShareSaved(share)
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
#endif
