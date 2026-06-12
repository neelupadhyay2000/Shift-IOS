import SwiftUI

/// User-selectable appearance override (Settings → Appearance).
///
/// Persisted by raw value via `@AppStorage`; `system` defers to the device.
/// Applied once at `RootContainerView` so every screen follows — the sign-in
/// flow alone keeps its fixed-dark brand splash via its own
/// `preferredColorScheme`, which wins as the deeper preference.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let defaultsKey = "appearance.preference"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    /// `nil` defers to the system appearance.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
