import Models
import Services
import SwiftUI

/// Editor sheet for a user-created template: name, description, category,
/// and the block list (edit, add, remove).
///
/// Works on value copies — nothing is persisted until Save, which hands the
/// rebuilt `Template` (same ID, so the stored file is overwritten in place)
/// back to the caller.
struct TemplateEditorSheet: View {

    let template: Template
    let onSave: (Template) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var details: String
    @State private var category: TemplateCategory
    @State private var blocks: [EditableTemplateBlock]

    init(template: Template, onSave: @escaping (Template) -> Void) {
        self.template = template
        self.onSave = onSave
        _name = State(initialValue: template.name)
        _details = State(initialValue: template.description)
        _category = State(initialValue: template.category)
        _blocks = State(initialValue: template.blocks.map(EditableTemplateBlock.init))
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !blocks.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Template Details")) {
                    TextField(String(localized: "Template Name"), text: $name)
                        .accessibilityIdentifier(AccessibilityID.Templates.editorNameField)
                    TextField(String(localized: "Description"), text: $details, axis: .vertical)
                        .lineLimit(2...4)
                    Picker(String(localized: "Category"), selection: $category) {
                        ForEach(TemplateCategory.allCases, id: \.self) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                }

                Section {
                    ForEach($blocks) { $block in
                        NavigationLink {
                            EditableTemplateBlockForm(block: $block)
                        } label: {
                            EditableTemplateBlockRow(block: block)
                        }
                    }
                    .onDelete { offsets in
                        blocks.remove(atOffsets: offsets)
                    }

                    Button {
                        addBlock()
                    } label: {
                        Label(String(localized: "Add Block"), systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text(String(localized: "Blocks"))
                } footer: {
                    if blocks.isEmpty {
                        Text(String(localized: "A template needs at least one block."))
                    } else {
                        Text(String(localized: """
                        Swipe a block to delete it. Start times are offsets \
                        from the template's first block.
                        """))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { ProBackground() }
            .navigationTitle(String(localized: "Edit Template"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        saveEdits()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier(AccessibilityID.Templates.editorSaveButton)
                }
            }
        }
    }

    private func addBlock() {
        let lastEnd = blocks.map { $0.offsetMinutes + $0.durationMinutes }.max() ?? 0
        blocks.append(
            EditableTemplateBlock(
                title: String(localized: "New Block"),
                offsetMinutes: lastEnd,
                durationMinutes: 30
            )
        )
    }

    private func saveEdits() {
        // Re-anchor so the earliest block sits at offset 0 even after edits,
        // matching the invariant of templates captured from events.
        let earliestOffset = blocks.map(\.offsetMinutes).min() ?? 0
        let templateBlocks = blocks
            .sorted { $0.offsetMinutes < $1.offsetMinutes }
            .map { $0.templateBlock(rebasedBy: earliestOffset) }

        let updated = Template(
            id: template.id,
            name: name.trimmingCharacters(in: .whitespaces),
            description: details.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            blocks: templateBlocks
        )
        onSave(updated)
        dismiss()
    }
}

// MARK: - Editable block value

/// Mutable, minute-granularity working copy of a `TemplateBlock` for the editor.
/// `nonisolated` opts the plain value type out of the app target's default
/// `@MainActor` isolation so unapplied references like `map(Editable…init)`
/// convert without an isolation mismatch.
private nonisolated struct EditableTemplateBlock: Identifiable {
    let id = UUID()
    var title: String
    var offsetMinutes: Int
    var durationMinutes: Int
    var isPinned: Bool = false
    var colorTag: String = "#007AFF"
    var icon: String = "circle.fill"

    init(title: String, offsetMinutes: Int, durationMinutes: Int) {
        self.title = title
        self.offsetMinutes = offsetMinutes
        self.durationMinutes = durationMinutes
    }

    init(_ block: TemplateBlock) {
        title = block.title
        offsetMinutes = Int(block.relativeStartOffset) / 60
        durationMinutes = Int(block.duration) / 60
        isPinned = block.isPinned
        colorTag = block.colorTag
        icon = block.icon
    }

    func templateBlock(rebasedBy earliestOffset: Int) -> TemplateBlock {
        TemplateBlock(
            title: title.trimmingCharacters(in: .whitespaces),
            relativeStartOffset: TimeInterval((offsetMinutes - earliestOffset) * 60),
            duration: TimeInterval(max(1, durationMinutes) * 60),
            isPinned: isPinned,
            colorTag: colorTag,
            icon: icon
        )
    }
}

// MARK: - Block row

private struct EditableTemplateBlockRow: View {

    let block: EditableTemplateBlock

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: block.icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color(hex: block.colorTag), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(block.title)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    Text(formattedOffset)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(DurationFormatter.compact(minutes: block.durationMinutes))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if block.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var formattedOffset: String {
        let hours = block.offsetMinutes / 60
        let minutes = block.offsetMinutes % 60
        return "+\(hours):\(String(format: "%02d", minutes))"
    }
}

// MARK: - Block form

private struct EditableTemplateBlockForm: View {

    @Binding var block: EditableTemplateBlock

    var body: some View {
        Form {
            Section(String(localized: "Block")) {
                TextField(String(localized: "Title"), text: $block.title)
                Toggle(String(localized: "Pinned"), isOn: $block.isPinned)
            }

            Section {
                Stepper(value: $block.offsetMinutes, in: 0...1440, step: 5) {
                    LabeledContent(String(localized: "Starts After")) {
                        Text(DurationFormatter.compact(minutes: block.offsetMinutes))
                            .monospacedDigit()
                    }
                }
                Stepper(value: $block.durationMinutes, in: 5...1440, step: 5) {
                    LabeledContent(String(localized: "Duration")) {
                        Text(DurationFormatter.compact(minutes: block.durationMinutes))
                            .monospacedDigit()
                    }
                }
            } footer: {
                Text(String(localized: "“Starts After” is the offset from the template's first block."))
            }
        }
        .scrollContentBackground(.hidden)
        .background { ProBackground() }
        .navigationTitle(block.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
