import CoreLocation
import Observation
import SwiftUI

/// The caller's coarse location for marketplace distance + "Nearest" sorting.
///
/// **Opt-in by design.** The directory never prompts on appear; the user asks for
/// it by choosing "Nearest" or tapping the distance affordance. Until then
/// `coordinate` is nil, `search_vendors` receives no point, and the backend's
/// `distance_km` stays NULL — exactly the pre-existing behaviour.
///
/// Uses `requestLocation()` (a single fix) rather than continuous updates: a
/// directory needs one coarse point, not a location stream. Accuracy is
/// deliberately reduced to ~3km — the cards show "12 km away", not turn-by-turn.
@MainActor
@Observable
final class MarketplaceLocationProvider: NSObject, CLLocationManagerDelegate {

    /// The caller's last known point, or nil when unavailable/undetermined/denied.
    private(set) var coordinate: CLLocationCoordinate2D?
    /// True while a fix is in flight, so the UI can show a spinner on the control.
    private(set) var isResolving = false
    private(set) var authorization: CLAuthorizationStatus

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        // A vendor directory does not need street-level precision.
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    /// True when we can supply a point today (already authorized).
    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    /// True when the user has said no — the UI should stop offering the control.
    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    /// Asks for permission if needed, then resolves a single fix.
    /// Safe to call repeatedly; a no-op while a fix is already in flight.
    func requestLocation() {
        guard !isResolving, !isDenied else { return }
        switch authorization {
        case .notDetermined:
            // The delegate kicks off the fix once the user answers.
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            isResolving = true
            manager.requestLocation()
        default:
            break
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            authorization = status
            // Permission just granted → complete the request the user started.
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                guard !isResolving else { return }
                isResolving = true
                manager.requestLocation()
            } else {
                isResolving = false
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let point = locations.last?.coordinate
        Task { @MainActor in
            isResolving = false
            if let point { coordinate = point }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            isResolving = false
            // Leave `coordinate` as-is: a stale point beats no point for sorting.
        }
    }
}

// MARK: - Environment

private struct MarketplaceLocationProviderKey: EnvironmentKey {
    static let defaultValue: MarketplaceLocationProvider? = nil
}

extension EnvironmentValues {
    var marketplaceLocation: MarketplaceLocationProvider? {
        get { self[MarketplaceLocationProviderKey.self] }
        set { self[MarketplaceLocationProviderKey.self] = newValue }
    }
}

// MARK: - Distance formatting

enum VendorDistance {
    /// "820 m away" / "12 km away" — coarse, matching the reduced accuracy we ask for.
    static func label(km: Double) -> String {
        if km < 1 {
            return String(localized: "\(Int((km * 1000).rounded(.toNearestOrEven))) m away")
        }
        if km < 10 {
            return String(localized: "\(km.formatted(.number.precision(.fractionLength(1)))) km away")
        }
        return String(localized: "\(Int(km.rounded())) km away")
    }
}
