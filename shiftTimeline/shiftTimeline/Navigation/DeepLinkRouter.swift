import CoreData
import Foundation
import SwiftUI

/// The action the router should perform when a deep-link arrives.
enum DeepLinkDestination: Equatable {
    case event(id: UUID)
    case live(id: UUID)
    case roster
    /// Pushes directly to TimelineBuilderView with EventDetailView in back stack (used after template apply).
    case newEventTimeline(id: UUID)
}

/// Observable deep-link router. Inject via `.environment()` at app root.
/// `RootNavigator` observes `pendingDestination` and routes accordingly.
@MainActor
@Observable
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    /// Auto-clears syncing indicator if no remote-change notification arrives within this window.
    static let shareAcceptanceSyncTimeout: Duration = .seconds(30)

    var pendingDestination: DeepLinkDestination?

    /// `true` while a CKShare invitation is being accepted and records are syncing.
    /// `EventRosterView` observes this to show a syncing indicator.
    /// Auto-clears on `NSPersistentStoreRemoteChange` or after `shareAcceptanceSyncTimeout`.
    var isAcceptingShare = false {
        didSet {
            guard oldValue != isAcceptingShare else { return }
            shareTimeoutTask?.cancel()
            shareTimeoutTask = nil
            guard isAcceptingShare else { return }
            shareTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.shareAcceptanceSyncTimeout)
                guard !Task.isCancelled else { return }
                self?.isAcceptingShare = false
            }
        }
    }

    private var shareTimeoutTask: Task<Void, Never>?

    private init() {
        // Clear syncing banner when the persistent store mirrors a remote change.
        // Observer not stored — `DeepLinkRouter` is a process-lifetime singleton.
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isAcceptingShare else { return }
                self.isAcceptingShare = false
            }
        }
    }

    /// Convenience — kept for backward compatibility with existing callers.
    var pendingEventID: UUID? {
        get {
            if case .event(let id) = pendingDestination { return id }
            return nil
        }
        set {
            if let id = newValue {
                pendingDestination = .event(id: id)
            } else if case .event = pendingDestination {
                pendingDestination = nil
            }
        }
    }

    // MARK: - URL Parsing

    /// Parses `shift://event/{id}` and `shift://live/{id}` URLs. Returns `true` if handled.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard url.scheme == "shift",
              let host = url.host else { return false }

        // Support both shift://event/UUID and shift://event?id=UUID
        let rawID: String
        if let queryID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "id" })?.value {
            rawID = queryID
        } else if url.pathComponents.count > 1 {
            rawID = url.pathComponents[1]
        } else {
            return false
        }

        guard let eventID = UUID(uuidString: rawID) else { return false }

        switch host {
        case "event":
            pendingDestination = .event(id: eventID)
            return true
        case "live":
            pendingDestination = .live(id: eventID)
            return true
        default:
            return false
        }
    }
}
