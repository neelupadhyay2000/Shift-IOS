import SwiftUI
import SwiftData
import Models
import Services

/// Full preview of a template showing all blocks in a scrollable list.
/// The "Use This Template" button creates a new event with pre-populated blocks.
struct TemplatePreviewView: View {

    let templateID: UUID
    @Binding var templatePath: [TemplateDestination]

    @Environment(\.modelContext) private var modelContext

    @State private var template: Template?
    @State private var loadError: String?
    @State private var isShowingCreateSheet = false

    var body: some View {
        Group {
            if let template {
                templateContent(template)
            } else if let loadError {
                ContentUnavailableView(
                    String(localized: "Unable to Load Template"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else {
                ProgressView()
            }
        }
        .navigationTitle(template?.name ?? String(localized: "Template"))
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadTemplate()
        }
        .sheet(isPresented: $isShowingCreateSheet) {
            if let template {
                UseTemplateSheet(template: template) { eventID in
                    templatePath.append(.timelineBuilder(eventID: eventID))
                }
            }
        }
    }

    private func templateContent(_ template: Template) -> some View {
        List {
            Section {
                Text(template.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Label("\(template.blocks.count) blocks", systemImage: "rectangle.stack")
                    Label(formattedDuration(template), systemImage: "clock")
                    Spacer()
                    Text(template.category.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(template.category.tintColor.opacity(0.15))
                        .foregroundStyle(template.category.tintColor)
                        .clipShape(Capsule())
                }
                .font(.subheadline)

                Button {
                    isShowingCreateSheet = true
                } label: {
                    Label(String(localized: "Use This Template"), systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }

            Section(String(localized: "Blocks")) {
                ForEach(Array(template.blocks.enumerated()), id: \.offset) { _, block in
                    TemplateBlockRow(block: block)
                }
            }
        }
    }

    private func loadTemplate() async {
        do {
            let loaded = try await Task.detached {
                try TemplateLoader().loadAll()
            }.value
            template = loaded.first { $0.id == templateID }
            if template == nil {
                loadError = String(localized: "Template not found.")
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func formattedDuration(_ template: Template) -> String {
        let totalSeconds = template.blocks.map { $0.relativeStartOffset + $0.duration }.max() ?? 0
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        if minutes > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(hours)h"
    }
}

// MARK: - Use Template Sheet

/// Sheet that collects event name, date, and start time, then creates the event
/// with all template blocks pre-populated.
private struct UseTemplateSheet: View {

    let template: Template
    let onEventCreated: (UUID) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var eventTitle: String = ""
    @State private var eventDate: Date = .now
    @State private var startTime: Date = Calendar.current.date(
        bySettingHour: 10, minute: 0, second: 0, of: .now
    ) ?? .now

    private var canCreate: Bool {
        !eventTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Event Details")) {
                    TextField(String(localized: "Event Name"), text: $eventTitle)
                    DatePicker(String(localized: "Date"), selection: $eventDate, displayedComponents: .date)
                    DatePicker(String(localized: "Start Time"), selection: $startTime, displayedComponents: .hourAndMinute)
                }

                Section {
                    LabeledContent(String(localized: "Template")) {
                        Text(template.name)
                    }
                    LabeledContent(String(localized: "Blocks")) {
                        Text("\(template.blocks.count)")
                    }
                }
            }
            .navigationTitle(String(localized: "New Event from Template"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Create")) {
                        let eventID = createEventFromTemplate()
                        dismiss()
                        onEventCreated(eventID)
                    }
                    .disabled(!canCreate)
                }
            }
        }
    }

    private func createEventFromTemplate() -> UUID {
        let trimmedTitle = eventTitle.trimmingCharacters(in: .whitespaces)

        let event = EventModel(
            title: trimmedTitle,
            date: eventDate,
            latitude: 0,
            longitude: 0
        )
        modelContext.insert(event)

        let mainTrack = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        modelContext.insert(mainTrack)

        let baseStart = combineDateAndTime(date: eventDate, time: startTime)

        for templateBlock in template.blocks {
            let blockStart = baseStart.addingTimeInterval(templateBlock.relativeStartOffset)
            let block = TimeBlockModel(
                title: templateBlock.title,
                scheduledStart: blockStart,
                duration: templateBlock.duration,
                isPinned: templateBlock.isPinned,
                colorTag: templateBlock.colorTag,
                icon: templateBlock.icon
            )
            block.track = mainTrack
            modelContext.insert(block)
        }

        return event.id
    }

    private func combineDateAndTime(date: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        var combined = DateComponents()
        combined.year = dateComponents.year
        combined.month = dateComponents.month
        combined.day = dateComponents.day
        combined.hour = timeComponents.hour
        combined.minute = timeComponents.minute
        return calendar.date(from: combined) ?? date
    }
}

// MARK: - Block Row

private struct TemplateBlockRow: View {

    let block: TemplateBlock

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: block.icon)
                .font(.body)
                .foregroundStyle(Color(hex: block.colorTag))
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(block.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Text(formattedOffset)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if block.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var formattedOffset: String {
        let totalMinutes = Int(block.relativeStartOffset) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "+\(hours):\(String(format: "%02d", minutes))"
    }

    private var formattedDuration: String {
        let minutes = Int(block.duration) / 60
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
        return "\(minutes)m"
    }
}
