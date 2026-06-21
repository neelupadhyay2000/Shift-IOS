import SwiftUI
import SwiftData
import MapKit
import TipKit
import Models
import Services

/// Sheet for creating a new event.
///
/// Fields: Title (required), Date, Location (optional address search).
/// The "Create" button is disabled when title is empty.
struct CreateEventSheet: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.eventRepository) private var injectedEventRepo
    @Environment(\.trackRepository) private var injectedTrackRepo

    private var eventRepo: any EventRepositing {
        injectedEventRepo ?? SwiftDataEventRepository(context: modelContext)
    }
    private var trackRepo: any TrackRepositing {
        injectedTrackRepo ?? SwiftDataTrackRepository(context: modelContext)
    }

    @State private var title: String = ""
    @State private var date: Date = .now
    @State private var locationResult: BlockLocationResult? = nil

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Title"), text: $title)
                        .accessibilityIdentifier(AccessibilityID.EventCreation.titleField)
                    DatePickerRow(String(localized: "Date"), selection: $date, components: .date)
                        .accessibilityIdentifier(AccessibilityID.EventCreation.datePicker)
                }

                Section(String(localized: "Location")) {
                    BlockLocationPickerView(
                        currentAddress: locationResult?.venueAddress ?? "",
                        currentVenueName: locationResult?.venueName ?? ""
                    ) { result in
                        locationResult = result.coordinate == nil ? nil : result
                    }
                }
            }
            .navigationTitle(String(localized: "New Event"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                    .accessibilityIdentifier(AccessibilityID.EventCreation.cancelButton)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Create")) {
                        Task { await createEvent() }
                    }
                    .disabled(!canCreate)
                    .accessibilityHint(canCreate ? "" : String(localized: "Enter an event title to continue"))
                    .accessibilityIdentifier(AccessibilityID.EventCreation.createButton)
                }
            }
        }
    }

    @MainActor
    private func createEvent() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let latitude = locationResult?.coordinate?.latitude ?? 0
        let longitude = locationResult?.coordinate?.longitude ?? 0
        let venueNames: [String] = {
            guard let name = locationResult?.venueName, !name.isEmpty else { return [] }
            return [name]
        }()

        let event = EventModel(
            title: trimmedTitle,
            date: date,
            latitude: latitude,
            longitude: longitude,
            venueNames: venueNames
        )
        try? await eventRepo.insert(event)
        AnalyticsService.send(.eventCreated)
        AddBlockTip.hasCreatedFirstEvent = true

        let mainTrack = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        try? await trackRepo.insert(mainTrack, into: event)

        if latitude != 0 && longitude != 0 {
            let service = SunsetService()
            _ = await service.fetchIfNeeded(for: event)
        }
        try? await eventRepo.save()
        // Evening-before briefing; re-stamped on every foreground so it picks
        // up blocks and sunset data added after creation.
        await DayBeforeBriefingNotifier.schedule(for: event)
        // Golden-hour / sunset reminder, armed at planning time (sun times were
        // just fetched above). No-ops when the event has no location or the
        // 30-min lead has already passed.
        await GoldenHourNotifier.schedule(for: event)
        dismiss()
    }
}

#Preview {
    CreateEventSheet()
        .modelContainer(try! PersistenceController.forTesting())
}
