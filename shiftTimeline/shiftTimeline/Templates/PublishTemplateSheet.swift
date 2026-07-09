import Models
import SwiftUI

/// Publishes a template to the community library. Confirms name / description /
/// category (prefilled from the source template) then calls the gated
/// `publish_community_template` RPC.
///
/// `sourceEventID` (set when publishing straight from an event) earns the
/// "Verified — run in Shift" badge — but only when the server confirms that event
/// is completed and owned by the caller. Library publishes pass `nil` (unverified).
struct PublishTemplateSheet: View {

    let template: Template
    let sourceEventID: UUID?

    @Environment(\.communityTemplateService) private var service
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var details: String
    @State private var category: TemplateCategory
    @State private var isPublishing = false
    @State private var publishError: String?

    init(template: Template, sourceEventID: UUID? = nil) {
        self.template = template
        self.sourceEventID = sourceEventID
        _name = State(initialValue: template.name)
        _details = State(initialValue: template.description)
        _category = State(initialValue: template.category)
    }

    private var canPublish: Bool {
        service != nil
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !template.blocks.isEmpty
            && !isPublishing
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Template Details")) {
                    TextField(String(localized: "Template Name"), text: $name)
                    TextField(String(localized: "Description"), text: $details, axis: .vertical)
                        .lineLimit(2...4)
                    Picker(String(localized: "Category"), selection: $category) {
                        ForEach(TemplateCategory.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                }

                Section {
                    LabeledContent(String(localized: "Blocks")) {
                        Text("\(template.blocks.count)").monospacedDigit()
                    }
                } footer: {
                    Text(String(localized: """
                    Your template will be visible to everyone in the community library. \
                    Don’t include private client names or personal details. \
                    Block times are shared relative to the first block, never real dates.
                    """))
                }

                if let publishError {
                    Section {
                        Text(publishError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { ProBackground() }
            .navigationTitle(String(localized: "Publish to Community"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isPublishing {
                        ProgressView()
                    } else {
                        Button(String(localized: "Publish")) {
                            Task { await publish() }
                        }
                        .disabled(!canPublish)
                    }
                }
            }
        }
    }

    private func publish() async {
        guard let service else { return }
        isPublishing = true
        publishError = nil
        defer { isPublishing = false }

        // Publish the edited metadata with the original blocks.
        let edited = Template(
            name: name.trimmingCharacters(in: .whitespaces),
            description: details.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            blocks: template.blocks
        )
        do {
            _ = try await service.publish(edited, sourceEventID: sourceEventID)
            AnalyticsService.send(.communityTemplatePublished, parameters: [
                "verifiedSource": sourceEventID != nil ? "true" : "false",
                "blockCount": "\(edited.blocks.count)",
            ])
            dismiss()
        } catch {
            publishError = String(localized: "Couldn’t publish. Please check your connection and try again.")
        }
    }
}
