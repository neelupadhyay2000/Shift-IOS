import SwiftUI
import Models
import Services

/// Root of the Templates tab.
///
/// A segmented control splits the tab into two spaces:
/// - **Library** — the user's own saved templates ("My Templates", created via
///   "Save as Template" on an event; editable and deletable) above the bundled
///   starter templates.
/// - **Community** — coming-soon teaser for shared community templates.
struct TemplateBrowserView: View {

    /// Top-level segments of the Templates tab.
    private enum TemplateSection: String, CaseIterable, Identifiable {
        case library
        case community

        var id: String { rawValue }

        var label: String {
            switch self {
            case .library: String(localized: "Library")
            case .community: String(localized: "Community")
            }
        }
    }

    @State private var section: TemplateSection = .library
    @State private var starterTemplates: [Template] = []
    @State private var userTemplates: [Template] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var editingTemplate: Template?
    @State private var templatePendingDeletion: Template?

    private let userStore = UserTemplateStore()

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker(String(localized: "Section"), selection: $section) {
                    ForEach(TemplateSection.allCases) { section in
                        Text(section.label).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 4)
                .accessibilityIdentifier(AccessibilityID.Templates.sectionPicker)

                switch section {
                case .library:
                    libraryContent
                case .community:
                    CommunityTemplatesTeaserView()
                }
            }
        }
        .background { ProBackground() }
        .accessibilityIdentifier(AccessibilityID.Templates.templateList)
        .navigationTitle(String(localized: "Templates"))
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadStarterTemplates()
            reloadUserTemplates()
        }
        // Re-fires when popping back from a preview where the user may have
        // edited or deleted a template (`.task` won't — the view never left
        // the hierarchy).
        .onAppear {
            reloadUserTemplates()
        }
        .sheet(item: $editingTemplate) { template in
            TemplateEditorSheet(template: template) { updated in
                persistEdits(updated)
            }
        }
        .confirmationDialog(
            String(localized: "Delete Template?"),
            isPresented: Binding(
                get: { templatePendingDeletion != nil },
                set: { if !$0 { templatePendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: templatePendingDeletion
        ) { template in
            Button(String(localized: "Delete"), role: .destructive) {
                delete(template)
            }
        } message: { template in
            Text(String(localized: """
            “\(template.name)” will be removed from My Templates. \
            Events created from it are not affected.
            """))
        }
    }

    // MARK: - Library

    @ViewBuilder
    private var libraryContent: some View {
        if let loadError {
            ContentUnavailableView(
                String(localized: "Unable to Load Templates"),
                systemImage: "exclamationmark.triangle",
                description: Text(loadError)
            )
        } else if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
        } else if starterTemplates.isEmpty && userTemplates.isEmpty {
            ContentUnavailableView(
                String(localized: "No Templates"),
                systemImage: "square.grid.2x2",
                description: Text(String(localized: "Templates will appear here."))
            )
        } else {
            VStack(alignment: .leading, spacing: 24) {
                if !userTemplates.isEmpty {
                    myTemplatesSection
                }
                starterTemplatesSection
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    private var myTemplatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "My Templates")).microLabel()

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(userTemplates) { template in
                    NavigationLink(value: TemplateDestination.templatePreview(templateID: template.id)) {
                        TemplateCardView(template: template)
                    }
                    .buttonStyle(.pressableCard)
                    .contextMenu {
                        Button {
                            editingTemplate = template
                        } label: {
                            Label(String(localized: "Edit"), systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            templatePendingDeletion = template
                        } label: {
                            Label(String(localized: "Delete"), systemImage: "trash")
                        }
                    }
                }
            }
            .accessibilityIdentifier(AccessibilityID.Templates.myTemplatesGrid)
        }
    }

    private var starterTemplatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !userTemplates.isEmpty {
                Text(String(localized: "Starter Templates")).microLabel()
            }

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(starterTemplates) { template in
                    NavigationLink(value: TemplateDestination.templatePreview(templateID: template.id)) {
                        TemplateCardView(template: template)
                    }
                    .buttonStyle(.pressableCard)
                }
            }
            .accessibilityIdentifier(AccessibilityID.Templates.starterTemplatesGrid)
        }
    }

    // MARK: - Loading & mutations

    private func loadStarterTemplates() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let loaded = try await Task(priority: .userInitiated) {
                try TemplateLoader().loadAll().sorted { $0.name < $1.name }
            }.value
            guard !Task.isCancelled else { return }
            starterTemplates = loaded
        } catch {
            guard !Task.isCancelled else { return }
            loadError = error.localizedDescription
        }
    }

    private func reloadUserTemplates() {
        userTemplates = (try? userStore.loadAll()) ?? []
    }

    private func persistEdits(_ template: Template) {
        do {
            try userStore.save(template)
            AnalyticsService.send(.templateEdited)
        } catch {
            loadError = error.localizedDescription
        }
        reloadUserTemplates()
    }

    private func delete(_ template: Template) {
        do {
            try userStore.delete(id: template.id)
            AnalyticsService.send(.templateDeleted)
        } catch {
            loadError = error.localizedDescription
        }
        reloadUserTemplates()
    }
}

// MARK: - Template Card

private struct TemplateCardView: View {

    let template: Template

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The mini-timeline carries the personality; the chrome stays quiet.
            Text(template.category.displayName).microLabel()

            timelineThumbnail
                .frame(height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(template.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            Text(template.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 4) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 10, weight: .medium))
                Text("\(template.blocks.count)")
                    .monospacedDigit()
                Text(String(localized: "blocks"))
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .proCard(padding: 12)
    }

    /// Mini timeline thumbnail showing colored bars for each block.
    private var timelineThumbnail: some View {
        GeometryReader { geometry in
            let totalDuration = templateTotalDuration
            if totalDuration > 0 {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.tertiarySystemFill))

                    ForEach(Array(template.blocks.enumerated()), id: \.offset) { _, block in
                        let xOffset = geometry.size.width * (block.relativeStartOffset / totalDuration)
                        let width = max(2, geometry.size.width * (block.duration / totalDuration))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: block.colorTag))
                            .frame(width: width, height: block.isPinned ? 40 : 28)
                            .offset(x: xOffset)
                    }
                }
            }
        }
    }

    private var templateTotalDuration: TimeInterval {
        template.blocks.map { $0.relativeStartOffset + $0.duration }.max() ?? 1
    }
}

// MARK: - TemplateCategory Display Helpers

extension TemplateCategory {
    var displayName: String {
        switch self {
        case .wedding: String(localized: "Wedding")
        case .corporate: String(localized: "Corporate")
        case .social: String(localized: "Social")
        case .photography: String(localized: "Photography")
        }
    }
}
