import SwiftUI
import SwiftData
import Services

// MARK: - Environment keys for the five repository protocols.
//
// Default is nil; views fall back to a SwiftData-backed instance built from
// the ambient modelContext when no provider is injected. Use
// `.repositories(_:)` to inject a `RepositoryProviding` in one call.

private struct EventRepositoryKey: EnvironmentKey {
    static let defaultValue: (any EventRepositing)? = nil
}
private struct TrackRepositoryKey: EnvironmentKey {
    static let defaultValue: (any TrackRepositing)? = nil
}
private struct BlockRepositoryKey: EnvironmentKey {
    static let defaultValue: (any BlockRepositing)? = nil
}
private struct VendorRepositoryKey: EnvironmentKey {
    static let defaultValue: (any VendorRepositing)? = nil
}
private struct ShiftRecordRepositoryKey: EnvironmentKey {
    static let defaultValue: (any ShiftRecordRepositing)? = nil
}

/// The cutover's shared ``RealtimeEchoSuppressor`` (SHIFT-658). Injected by the
/// app when `FeatureFlags.supabaseSync` is on so the per-event realtime applier
/// in `EventDetailView` consults the *same* instance the Outbox flush records
/// into — that's what lets the planner's own writes be recognized as echoes and
/// skipped. `nil` when sync is off (no realtime), so the applier suppresses
/// nothing.
private struct RealtimeEchoSuppressorKey: EnvironmentKey {
    static let defaultValue: RealtimeEchoSuppressor? = nil
}

extension EnvironmentValues {
    var eventRepository: (any EventRepositing)? {
        get { self[EventRepositoryKey.self] }
        set { self[EventRepositoryKey.self] = newValue }
    }
    var trackRepository: (any TrackRepositing)? {
        get { self[TrackRepositoryKey.self] }
        set { self[TrackRepositoryKey.self] = newValue }
    }
    var blockRepository: (any BlockRepositing)? {
        get { self[BlockRepositoryKey.self] }
        set { self[BlockRepositoryKey.self] = newValue }
    }
    var vendorRepository: (any VendorRepositing)? {
        get { self[VendorRepositoryKey.self] }
        set { self[VendorRepositoryKey.self] = newValue }
    }
    var shiftRecordRepository: (any ShiftRecordRepositing)? {
        get { self[ShiftRecordRepositoryKey.self] }
        set { self[ShiftRecordRepositoryKey.self] = newValue }
    }
    var realtimeEchoSuppressor: RealtimeEchoSuppressor? {
        get { self[RealtimeEchoSuppressorKey.self] }
        set { self[RealtimeEchoSuppressorKey.self] = newValue }
    }
}

// MARK: - View injection modifier

extension View {
    /// Injects a `RepositoryProviding` bundle into the SwiftUI environment,
    /// populating all five per-aggregate repository keys in one call.
    ///
    /// ```swift
    /// // Production (scene level):
    /// ContentView()
    ///     .repositories(SwiftDataRepositoryProvider(context: container.mainContext))
    ///
    /// // Tests / previews:
    /// MyView()
    ///     .repositories(FakeRepositoryProvider())
    /// ```
    @MainActor func repositories(_ provider: any RepositoryProviding) -> some View {
        self
            .environment(\.eventRepository, provider.events)
            .environment(\.trackRepository, provider.tracks)
            .environment(\.blockRepository, provider.blocks)
            .environment(\.vendorRepository, provider.vendors)
            .environment(\.shiftRecordRepository, provider.shiftRecords)
    }
}
