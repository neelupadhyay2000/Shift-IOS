import SwiftUI
import SwiftData
import Services

// MARK: - Environment keys for the five repository protocols.
//
// Default is nil; views fall back to a SwiftData-backed instance built from
// the ambient modelContext. SHIFT-527 wires in real injection (and fakes for
// tests), at which point the nil branch is never reached in production.

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
}
