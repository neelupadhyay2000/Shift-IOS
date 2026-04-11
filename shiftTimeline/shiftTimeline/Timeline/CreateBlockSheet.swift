import SwiftUI
import SwiftData
import Models

/// Sheet for creating a new time block within an event.
///
/// Fields: Title (required), Start Time (DatePicker), Duration (preset picker),
/// Fluid/Pinned toggle. Saving inserts a `TimeBlockModel` into SwiftData.
struct CreateBlockSheet: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let eventID: UUID

    @State private var title = ""
    @State private var startTime = Date.now
    @State private var duration: TimeInterval = 1800
    @State private var isPinned = false

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
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
                        saveBlock()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func saveBlock() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)

        // Find or create a default track for this event
        let track = findOrCreateTrack()

        let block = TimeBlockModel(
            title: trimmedTitle,
            scheduledStart: startTime,
            duration: duration,
            isPinned: isPinned
        )
        block.track = track
        modelContext.insert(block)
        dismiss()
    }

    private func findOrCreateTrack() -> TimelineTrack {
        // Fetch the event to check for existing tracks
        var descriptor = FetchDescriptor<EventModel>(
            predicate: #Predicate { $0.id == eventID }
        )
        descriptor.fetchLimit = 1

        if let event = try? modelContext.fetch(descriptor).first,
           let existingTrack = event.tracks.first {
            return existingTrack
        }

        // Create a default track attached to the event
        let track = TimelineTrack(name: "Main", sortOrder: 0)
        if let event = try? modelContext.fetch(descriptor).first {
            track.event = event
        }
        modelContext.insert(track)
        return track
    }
}
