import SwiftUI
import SwiftData
import Models

/// Displays the details for a single event.
///
/// Fetched by `id` so the view works correctly whether pushed on iPhone
/// or shown in the iPad detail column.
struct EventDetailView: View {

    @Query private var results: [EventModel]

    private let eventID: UUID

    init(eventID: UUID) {
        self.eventID = eventID
        _results = Query(
            filter: #Predicate<EventModel> { $0.id == eventID }
        )
    }

    private var event: EventModel? { results.first }

    var body: some View {
        Group {
            if let event {
                eventContent(event)
            } else {
                ContentUnavailableView(
                    String(localized: "Event Not Found"),
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
        .navigationTitle(event?.title ?? String(localized: "Event"))
        .navigationBarTitleDisplayMode(.large)
    }

    private func eventContent(_ event: EventModel) -> some View {
        List {
            Section(String(localized: "Details")) {
                LabeledContent(String(localized: "Date")) {
                    Text(event.date, format: .dateTime.month(.wide).day().year())
                }
                LabeledContent(String(localized: "Status")) {
                    Text(event.status.label)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(event.status.tintColor.opacity(0.15))
                        .foregroundStyle(event.status.tintColor)
                        .clipShape(Capsule())
                }
                if !event.venueNames.isEmpty {
                    LabeledContent(String(localized: "Venue")) {
                        Text(event.venueNames.joined(separator: ", "))
                    }
                }
            }

            Section(String(localized: "Location")) {
                LabeledContent(String(localized: "Latitude")) {
                    Text(event.latitude, format: .number.precision(.fractionLength(4)))
                }
                LabeledContent(String(localized: "Longitude")) {
                    Text(event.longitude, format: .number.precision(.fractionLength(4)))
                }
                if let sunset = event.sunsetTime {
                    LabeledContent(String(localized: "Sunset")) {
                        Text(sunset, format: .dateTime.hour().minute())
                    }
                }
                if let golden = event.goldenHourStart {
                    LabeledContent(String(localized: "Golden Hour")) {
                        Text(golden, format: .dateTime.hour().minute())
                    }
                }
            }

            Section(String(localized: "Summary")) {
                LabeledContent(String(localized: "Tracks")) {
                    Text("\(event.tracks.count)")
                }
                LabeledContent(String(localized: "Vendors")) {
                    Text("\(event.vendors.count)")
                }
            }
        }
    }
}

// MARK: - EventStatus helpers used by EventRowView are reused here via the extension in EventRowView.swift
