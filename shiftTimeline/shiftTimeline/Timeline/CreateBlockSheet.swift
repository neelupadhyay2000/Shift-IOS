import SwiftUI
import SwiftData
import MapKit
import Models

/// Sheet for creating a new time block within an event.
///
/// Fields: Title (required), Start Time (DatePicker), Duration (preset picker),
/// Fluid/Pinned toggle. Saving inserts a `TimeBlockModel` into SwiftData.
struct CreateBlockSheet: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let eventID: UUID
    /// Track to assign the new block to. When nil, falls back to the default track.
    var trackID: UUID? = nil

    @State private var title = ""
    @State private var startTime = Date.now
    @State private var duration: TimeInterval = 1800
    @State private var isPinned = false
    @State private var venueAddress: String = ""
    @State private var venueName: String = ""
    @State private var blockLatitude: Double = 0
    @State private var blockLongitude: Double = 0
    @State private var startTimePickerID = UUID()
    @State private var startTimePickerTask: Task<Void, Never>?

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
                    DatePicker(String(localized: "Start Time"), selection: $startTime, displayedComponents: [.date, .hourAndMinute])
                        .id(startTimePickerID)
                        .onChange(of: startTime) { _, _ in
                            startTimePickerTask?.cancel()
                            startTimePickerTask = Task {
                                try? await Task.sleep(for: .seconds(0.15))
                                guard !Task.isCancelled else { return }
                                startTimePickerID = UUID()
                            }
                        }
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
            .onDisappear {
                startTimePickerTask?.cancel()
                startTimePickerTask = nil
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        saveBlock()
                    }
                    .disabled(!canSave)
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

    private func saveBlock() {
        guard let event = fetchEvent() else { return }

        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)

        // Prefer the explicitly selected track, then the default track, then first available
        let track: TimelineTrack
        if let trackID, let selected = (event.tracks ?? []).first(where: { $0.id == trackID }) {
            track = selected
        } else if let defaultTrack = (event.tracks ?? []).first(where: { $0.isDefault }) {
            track = defaultTrack
        } else {
            track = (event.tracks ?? []).first ?? createTrack(for: event)
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
        block.track = track
        modelContext.insert(block)
        dismiss()
    }

    private func createTrack(for event: EventModel) -> TimelineTrack {
        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true)
        track.event = event
        modelContext.insert(track)
        return track
    }
}
