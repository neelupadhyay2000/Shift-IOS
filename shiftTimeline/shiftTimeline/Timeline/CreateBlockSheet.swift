import SwiftUI
import SwiftData
import MapKit
import Models
import Services

/// Sheet for creating a new time block within an event.
///
/// Fields: Title (required), Start Time (DatePicker), Duration (preset picker),
/// Fluid/Pinned toggle. Saving inserts a `TimeBlockModel` into SwiftData.
struct CreateBlockSheet: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.blockRepository) private var injectedBlockRepo
    @Environment(\.trackRepository) private var injectedTrackRepo

    private var blockRepo: any BlockRepositing {
        injectedBlockRepo ?? SwiftDataBlockRepository(context: modelContext)
    }
    private var trackRepo: any TrackRepositing {
        injectedTrackRepo ?? SwiftDataTrackRepository(context: modelContext)
    }

    let eventID: UUID
    /// Track to assign the new block to. When nil, falls back to the default track.
    var trackID: UUID? = nil
    /// Pre-filled start time. When nil, defaults to `Date.now`.
    /// Pass the end time of the last existing block so the picker opens at the
    /// next available slot rather than the current clock time.
    var suggestedStartTime: Date? = nil

    @State private var title = ""
    @State private var startTime: Date
    @State private var duration: TimeInterval = 1800
    @State private var isPinned = false
    @State private var venueAddress: String = ""
    @State private var venueName: String = ""
    @State private var blockLatitude: Double = 0
    @State private var blockLongitude: Double = 0

    init(eventID: UUID, trackID: UUID? = nil, suggestedStartTime: Date? = nil) {
        self.eventID = eventID
        self.trackID = trackID
        self.suggestedStartTime = suggestedStartTime
        _startTime = State(initialValue: suggestedStartTime ?? .now)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && fetchEvent() != nil
    }

    static let durationOptions: [(String, TimeInterval)] = [
        ("5m", 300),
        ("10m", 600),
        ("15m", 900),
        ("30m", 1800),
        ("45m", 2700),
        ("1h", 3600),
        ("1h 30m", 5400),
        ("2h", 7200),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Title"), text: $title)
                    DatePickerRow(String(localized: "Start Time"), selection: $startTime, components: [.date, .hourAndMinute])
                }

                Section(String(localized: "Duration")) {
                    Picker(String(localized: "Duration"), selection: $duration) {
                        ForEach(Self.durationOptions, id: \.1) { label, value in
                            Text(label).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle(String(localized: "Pinned"), isOn: $isPinned)
                        .accessibilityHint(String(localized: "Pinned blocks stay at their scheduled time when the timeline shifts"))
                }

                Section(String(localized: "Venue Location")) {
                    BlockLocationPickerView(
                        currentAddress: venueAddress,
                        currentVenueName: venueName
                    ) { result in
                        venueAddress = result.venueAddress
                        venueName = result.venueName
                        blockLatitude = result.coordinate?.latitude ?? 0
                        blockLongitude = result.coordinate?.longitude ?? 0
                    }
                }
            }
            .navigationTitle(String(localized: "New Block"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        Task { await saveBlock() }
                    }
                    .disabled(!canSave)
                    .accessibilityHint(canSave ? "" : String(localized: "Enter a block title to continue"))
                }
            }
        }
    }

    private func fetchEvent() -> EventModel? {
        var descriptor = FetchDescriptor<EventModel>(
            predicate: #Predicate { $0.id == eventID }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    @MainActor
    private func saveBlock() async {
        guard let event = fetchEvent() else { return }

        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)

        // Prefer the explicitly selected track, then the default track, then first available
        let track: TimelineTrack
        if let trackID, let selected = (event.tracks ?? []).first(where: { $0.id == trackID }) {
            track = selected
        } else if let defaultTrack = (event.tracks ?? []).first(where: { $0.isDefault }) {
            track = defaultTrack
        } else if let existing = (event.tracks ?? []).first {
            track = existing
        } else {
            track = await createTrack(for: event)
        }

        let block = TimeBlockModel(
            title: trimmedTitle,
            scheduledStart: startTime,
            duration: duration,
            isPinned: isPinned
        )
        block.venueAddress = venueAddress
        block.venueName = venueName
        block.blockLatitude = blockLatitude
        block.blockLongitude = blockLongitude
        try? await blockRepo.insert(block, into: track)

        try? await blockRepo.save()

        // Planning heads-up: if rain is forecast for this block, or it overlaps
        // golden hour, post an immediate notice. Fire-and-forget so it never
        // blocks dismissing the sheet; the notifier snapshots primitives before
        // any network await.
        Task { await BlockPlanningNotifier.notifyForNewBlock(block, in: event) }

        dismiss()
    }

    @MainActor
    private func createTrack(for event: EventModel) async -> TimelineTrack {
        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true)
        try? await trackRepo.insert(track, into: event)
        return track
    }
}
