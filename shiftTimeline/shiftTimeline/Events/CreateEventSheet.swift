import SwiftUI
import SwiftData
import Models
import Services

/// Sheet for creating a new event.
///
/// Fields: Title (required), Date, Venue Name (optional).
/// The "Create" button is disabled when title is empty.
struct CreateEventSheet: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var date: Date = .now
    @State private var venueName: String = ""

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Title"), text: $title)
                    DatePicker(String(localized: "Date"), selection: $date, displayedComponents: .date)
                    TextField(String(localized: "Venue Name"), text: $venueName)
                }
            }
            .navigationTitle(String(localized: "New Event"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Create")) {
                        createEvent()
                    }
                    .disabled(!canCreate)
                }
            }
        }
    }

    private func createEvent() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedVenue = venueName.trimmingCharacters(in: .whitespaces)
        let venueNames = trimmedVenue.isEmpty ? [] : [trimmedVenue]

        let event = EventModel(
            title: trimmedTitle,
            date: date,
            latitude: 0,
            longitude: 0,
            venueNames: venueNames
        )
        modelContext.insert(event)

        // Auto-create the default "Main" track so blocks have
        // a home immediately — no lazy fallback needed.
        let mainTrack = TimelineTrack(name: "Main", sortOrder: 0, event: event)
        modelContext.insert(mainTrack)

        dismiss()
    }
}

#Preview {
    CreateEventSheet()
        .modelContainer(try! PersistenceController.forTesting())
}
