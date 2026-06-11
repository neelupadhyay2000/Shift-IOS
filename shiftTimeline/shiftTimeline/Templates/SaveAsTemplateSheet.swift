import Models
import Services
import SwiftData
import SwiftUI

/// Sheet that saves an event's current timeline as a reusable user template.
///
/// Block times are captured relative to the earliest block, so the saved
/// template is date-independent and behaves exactly like a bundled starter
/// template: it appears under "My Templates" in the browser and can be
/// previewed, applied, edited, and deleted.
struct SaveAsTemplateSheet: View {

    let event: EventModel

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var details: String = ""
    @State private var category: TemplateCategory = .social
    @State private var saveError: String?

    init(event: EventModel) {
        self.event = event
        _name = State(initialValue: event.title)
    }

    private var blocks: [TimeBlockModel] {
        (event.tracks ?? []).flatMap { $0.blocks ?? [] }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !blocks.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Template Details")) {
                    TextField(String(localized: "Template Name"), text: $name)
                        .accessibilityIdentifier(AccessibilityID.Templates.saveTemplateNameField)
                    TextField(String(localized: "Description"), text: $details, axis: .vertical)
                        .lineLimit(2...4)
                    Picker(String(localized: "Category"), selection: $category) {
                        ForEach(TemplateCategory.allCases, id: \.self) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                }

                Section {
                    LabeledContent(String(localized: "Blocks")) {
                        Text("\(blocks.count)").monospacedDigit()
                    }
                } footer: {
                    if blocks.isEmpty {
                        Text(String(localized: """
                        This event has no blocks yet. Add blocks to the timeline \
                        before saving it as a template.
                        """))
                    } else {
                        Text(String(localized: """
                        Block times are saved relative to the first block, \
                        so this template can be applied to any date.
                        """))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { ProBackground() }
            .navigationTitle(String(localized: "Save as Template"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        saveTemplate()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier(AccessibilityID.Templates.saveTemplateButton)
                }
            }
            .alert(
                String(localized: "Unable to Save Template"),
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                )
            ) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func saveTemplate() {
        let template = Template.captured(
            from: blocks,
            name: name.trimmingCharacters(in: .whitespaces),
            description: details.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category
        )
        do {
            try UserTemplateStore().save(template)
            AnalyticsService.send(.templateSavedFromEvent, parameters: ["blockCount": "\(template.blocks.count)"])
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
