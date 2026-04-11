import SwiftUI
import SwiftData
import Models

/// Inspector sheet for editing an existing time block.
///
/// All fields are copied into local `@State` on appear. "Save" writes changes
/// back to the model; "Cancel" dismisses without saving.
struct BlockInspectorView: View {

    @Environment(\.dismiss) private var dismiss

    let block: TimeBlockModel

    @State private var title: String = ""
    @State private var startTime: Date = .now
    @State private var duration: TimeInterval = 1800
    @State private var isPinned: Bool = false
    @State private var notes: String = ""
    @State private var colorTag: String = "#007AFF"
    @State private var icon: String = "circle.fill"

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Details")) {
                    TextField(String(localized: "Title"), text: $title)
                    DatePicker(String(localized: "Start Time"), selection: $startTime, displayedComponents: [.date, .hourAndMinute])
                }

                Section(String(localized: "Duration")) {
                    Picker(String(localized: "Duration"), selection: $duration) {
                        ForEach(CreateBlockSheet.durationOptions, id: \.1) { label, value in
                            Text(label).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle(String(localized: "Pinned"), isOn: $isPinned)
                }

                Section(String(localized: "Notes")) {
                    TextField(String(localized: "Notes"), text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section(String(localized: "Appearance")) {
                    Picker(String(localized: "Color"), selection: $colorTag) {
                        ForEach(Self.colorOptions, id: \.value) { option in
                            Label(option.label, systemImage: "circle.fill")
                                .foregroundStyle(Color(hex: option.value))
                                .tag(option.value)
                        }
                    }

                    Picker(String(localized: "Icon"), selection: $icon) {
                        ForEach(Self.iconOptions, id: \.systemImage) { option in
                            Label(option.label, systemImage: option.systemImage)
                                .tag(option.systemImage)
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Edit Block"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        saveChanges()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .onAppear {
            title = block.title
            startTime = block.scheduledStart
            duration = block.duration
            isPinned = block.isPinned
            notes = block.notes
            colorTag = block.colorTag
            icon = block.icon
        }
    }

    private func saveChanges() {
        block.title = title.trimmingCharacters(in: .whitespaces)
        block.scheduledStart = startTime
        block.duration = duration
        block.isPinned = isPinned
        block.notes = notes
        block.colorTag = colorTag
        block.icon = icon
        dismiss()
    }

    // MARK: - Options

    static let colorOptions: [(label: String, value: String)] = [
        ("Blue", "#007AFF"),
        ("Red", "#FF3B30"),
        ("Green", "#34C759"),
        ("Orange", "#FF9500"),
        ("Purple", "#AF52DE"),
        ("Pink", "#FF2D55"),
        ("Yellow", "#FFCC00"),
        ("Gray", "#8E8E93"),
    ]

    static let iconOptions: [(label: String, value: String, systemImage: String)] = [
        ("Ceremony", "ceremony", "heart.fill"),
        ("Dinner", "dinner", "fork.knife"),
        ("Music", "music", "music.note"),
        ("Photo", "photo", "camera.fill"),
        ("Speech", "speech", "mic.fill"),
        ("Travel", "travel", "car.fill"),
        ("Setup", "setup", "wrench.fill"),
        ("Custom", "custom", "circle.fill"),
    ]
}
