import Foundation
import Services
import Supabase
import SwiftUI

// MARK: - Row

/// One `app_config` row. `value` is jsonb, decoded straight into the typed payload.
nonisolated struct AppConfigRow<Value: Decodable>: Decodable {
    let value: Value
}

// MARK: - Protocol

/// Reads remote app configuration (`app_config`). Online-only, authenticated-only,
/// and never fatal: every caller falls back to the cached or compiled values.
protocol AppConfigProviding: Sendable {
    /// The free plan's limits, as configured on the backend.
    func fetchFreeTierLimits() async throws -> FreeTierLimits
}

// MARK: - Supabase implementation

@MainActor
struct SupabaseAppConfigService: AppConfigProviding {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func fetchFreeTierLimits() async throws -> FreeTierLimits {
        let rows: [AppConfigRow<FreeTierLimits>] = try await client
            .from("app_config")
            .select("value")
            .eq("key", value: "free_tier")
            .execute()
            .value
        guard let limits = rows.first?.value else { throw AppConfigError.missingKey("free_tier") }
        return limits
    }
}

enum AppConfigError: Error {
    case missingKey(String)
}

// MARK: - Refresh

extension AppConfigProviding {
    /// Best-effort refresh of the free-tier limits.
    ///
    /// Silent by design: a failure (offline, signed out, RLS) simply leaves the
    /// previously cached — or compiled — limits in force. The free plan must never
    /// depend on a network round-trip succeeding.
    @MainActor
    func refreshFreeTierLimits() async {
        guard let limits = try? await fetchFreeTierLimits() else { return }
        FreeTier.apply(limits)
    }
}

// MARK: - Environment

private struct AppConfigServiceKey: EnvironmentKey {
    static let defaultValue: (any AppConfigProviding)? = nil
}

extension EnvironmentValues {
    var appConfigService: (any AppConfigProviding)? {
        get { self[AppConfigServiceKey.self] }
        set { self[AppConfigServiceKey.self] = newValue }
    }
}
