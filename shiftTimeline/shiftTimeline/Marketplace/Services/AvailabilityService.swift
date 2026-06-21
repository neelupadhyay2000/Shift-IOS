import Foundation
import Supabase
import SwiftUI

// MARK: - Protocol

/// Vendor availability (E18). Online-only direct Supabase access, like the other
/// marketplace services. Reads the vendor's own calendar via `get_my_calendar`
/// (manual busy days + derived bookings) and toggles manual busy days on
/// `vendor_busy_dates` (owner-only RLS).
protocol AvailabilityProviding: Sendable {
    /// The calling vendor's busy days in `[from, to]` — manual + booked.
    func calendar(from: Date, to: Date) async throws -> [CalendarDayDTO]

    /// Mark a day busy (upsert; resurrects a previously cleared day).
    func markBusy(date: Date, note: String?) async throws

    /// Clear a manual busy day (soft-delete). No-op for booked days (not in this table).
    func clearBusy(date: Date) async throws
}

// MARK: - Supabase implementation

@MainActor
struct SupabaseAvailabilityService: AvailabilityProviding {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func calendar(from: Date, to: Date) async throws -> [CalendarDayDTO] {
        let params = GetMyCalendarParams(
            pFrom: CalendarDay.string(from: from),
            pTo: CalendarDay.string(from: to)
        )
        return try await client
            .rpc("get_my_calendar", params: params)
            .execute()
            .value
    }

    func markBusy(date: Date, note: String?) async throws {
        let uid = try await client.auth.session.user.id
        let payload = BusyDateUpsertDTO(
            profileID: uid,
            busyDate: CalendarDay.string(from: date),
            note: note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        )
        try await client
            .from("vendor_busy_dates")
            .upsert(payload, onConflict: "profile_id,busy_date")
            .execute()
    }

    func clearBusy(date: Date) async throws {
        let uid = try await client.auth.session.user.id
        try await client
            .from("vendor_busy_dates")
            .update(["deleted_at": SupabaseTimestamp.string(from: Date())])
            .eq("profile_id", value: uid.uuidString)
            .eq("busy_date", value: CalendarDay.string(from: date))
            .execute()
    }
}

private extension String {
    var nilIfBlank: String? { isEmpty ? nil : self }
}

// MARK: - Environment

private struct AvailabilityServiceKey: EnvironmentKey {
    static let defaultValue: (any AvailabilityProviding)? = nil
}

extension EnvironmentValues {
    var availabilityService: (any AvailabilityProviding)? {
        get { self[AvailabilityServiceKey.self] }
        set { self[AvailabilityServiceKey.self] = newValue }
    }
}
