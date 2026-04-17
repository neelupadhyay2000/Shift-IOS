import Foundation
import SwiftUI

/// Observable deep-link router that external systems (notification taps,
/// URL opens) use to drive navigation into `RootNavigator`.
///
/// Inject via `.environment()` at the app root. When `pendingEventID` is
/// set, `RootNavigator` switches to the Events tab and pushes the event
/// detail view.
@Observable
final class DeepLinkRouter {
    /// Shared instance used by `AppDelegate` to route notification taps.
    /// The app entry point assigns the same instance to the environment.
    static let shared = DeepLinkRouter()

    var pendingEventID: UUID?
}
