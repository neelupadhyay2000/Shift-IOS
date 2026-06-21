import CoreLocation
import Models
import PhotosUI
import SwiftUI

/// Vendor opt-in / profile editor. New vendors pass through a Terms-acceptance
/// gate (Guideline 1.2) before the form; returning vendors land straight on it,
/// prefilled. Saving writes the reserved identity columns on `profiles` and the
/// marketplace columns on `vendor_profiles` (search_name kept in sync) via
/// ``MarketplaceProviding/upsertMyVendorProfile(_:)``.
struct MyVendorProfileEditorView: View {

    @Environment(\.marketplaceService) private var service
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(MarketplaceDefaultsKey.termsAccepted) private var termsAccepted = false

    private enum Phase { case loading, terms, form, saving }

    @State private var phase: Phase = .loading
    @State private var input = VendorProfileInput()
    @State private var isExisting = false
    @State private var newSkill = ""
    @State private var avatarItem: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var errorMessage: String?

    private let categories: [VendorRole] = VendorRole.allCases

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .terms:
                termsGate
            case .form, .saving:
                formScroll
            }
        }
        .background { ProBackground() }
        .navigationTitle(String(localized: "Vendor profile"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: avatarItem) { _, item in
            guard let item else { return }
            Task { await uploadAvatar(item) }
        }
    }

    // MARK: Terms gate

    private var termsGate: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(ShiftPalette.accent)
                Text(String(localized: "Before you list"))
                    .font(.title2.weight(.bold))
                Text(String(localized: """
                Listing in the marketplace makes your business profile public to other \
                Shift users. There is zero tolerance for objectionable content or abusive \
                behavior — profiles and accounts that violate the Terms may be removed. \
                You can report or block users at any time.
                """))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    if let url = LegalContent.termsOfServiceURL { openURL(url) }
                } label: {
                    Label(String(localized: "View the full Terms"), systemImage: "doc.text")
                        .font(.subheadline.weight(.semibold))
                }

                Button {
                    termsAccepted = true
                    phase = .form
                } label: {
                    Text(String(localized: "I agree & continue"))
                        .font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(ShiftPalette.accent.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.pressableCard)
            }
            .padding(20)
            .frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
    }

    // MARK: Form

    private var formScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                avatarSection
                field(title: String(localized: "Business name")) {
                    TextField(String(localized: "Business name"), text: $input.businessName)
                        .textInputAutocapitalization(.words)
                        .proCard(padding: 14)
                }
                field(title: String(localized: "Bio")) {
                    TextField(String(localized: "What you do, in a sentence or two"),
                              text: $input.bio, axis: .vertical)
                        .lineLimit(3...6)
                        .proCard(padding: 14)
                }
                categorySection
                skillsSection
                field(title: String(localized: "Service area")) {
                    TextField(String(localized: "City, region"), text: $input.serviceArea)
                        .textInputAutocapitalization(.words)
                        .proCard(padding: 14)
                }
                listingSection
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if isExisting {
                    // Plain (value-less) links so this editor works from whatever
                    // stack hosts it — now the Settings tab, not the marketplace.
                    NavigationLink {
                        PortfolioEditorView()
                    } label: {
                        Label(String(localized: "Manage portfolio"), systemImage: "photo.on.rectangle.angled")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .proCard(padding: 6)
                    }
                    .buttonStyle(.pressableCard)

                    NavigationLink {
                        AvailabilityCalendarView()
                    } label: {
                        Label(String(localized: "Manage availability"), systemImage: "calendar")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .proCard(padding: 6)
                    }
                    .buttonStyle(.pressableCard)
                    .accessibilityIdentifier(AccessibilityID.Marketplace.manageAvailabilityButton)
                }
                saveButton
            }
            .padding(20)
            .frame(maxWidth: 560).frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.2), value: input.category)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func field<Content: View>(title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).microLabel()
            content()
        }
    }

    private var avatarSection: some View {
        HStack(spacing: 16) {
            avatarThumb
            PhotosPicker(selection: $avatarItem, matching: .images) {
                Label(isUploadingAvatar ? String(localized: "Uploading…") : String(localized: "Choose photo"),
                      systemImage: "photo")
                    .font(.subheadline.weight(.semibold))
            }
            .disabled(isUploadingAvatar)
            Spacer()
        }
    }

    @ViewBuilder
    private var avatarThumb: some View {
        let color = MarketplaceCategory.color(input.category.rawValue)
        ZStack {
            Circle().fill(ShiftPalette.soft(color))
            if isUploadingAvatar {
                ProgressView()
            } else if let urlString = input.avatarURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { ProgressView() }
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.fill").font(.system(size: 28)).foregroundStyle(color)
            }
        }
        .frame(width: 72, height: 72)
    }

    private var categorySection: some View {
        field(title: String(localized: "Category")) {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                    ForEach(categories, id: \.self) { role in
                        let color = ShiftDesign.roleColor(for: role)
                        let isSelected = input.category == role
                        Button { input.category = role } label: {
                            HStack(spacing: 6) {
                                Image(systemName: role.systemImage).font(.caption)
                                Text(role.displayName).font(.caption.weight(isSelected ? .semibold : .medium)).lineLimit(1)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(isSelected ? .white : color)
                            .background(isSelected ? AnyShapeStyle(color.gradient) : AnyShapeStyle(ShiftPalette.soft(color)), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if input.category == .custom {
                    TextField(String(localized: "Vendor type (e.g. Videographer)"), text: $input.customCategoryLabel)
                        .textInputAutocapitalization(.words)
                        .proCard(padding: 14)
                }
            }
        }
    }

    private var skillsSection: some View {
        field(title: String(localized: "Skills")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField(String(localized: "Add a skill"), text: $newSkill)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .onSubmit(addSkill)
                    Button(action: addSkill) { Image(systemName: "plus.circle.fill") }
                        .disabled(newSkill.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .proCard(padding: 14)

                if !input.skills.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                        ForEach(input.skills, id: \.self) { skill in
                            HStack(spacing: 5) {
                                Text(skill.capitalized).font(.caption.weight(.medium)).lineLimit(1)
                                Button { input.skills.removeAll { $0 == skill } } label: {
                                    Image(systemName: "xmark.circle.fill").font(.caption2)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(ShiftPalette.soft(ShiftPalette.neutral), in: Capsule())
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var listingSection: some View {
        Toggle(isOn: $input.isListed) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "List in the marketplace")).font(.subheadline.weight(.semibold))
                Text(String(localized: "Visible to other Shift users. Requires a business name."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .tint(ShiftPalette.accent)
        .proCard(padding: 14)
    }

    private var saveButton: some View {
        Button { Task { await save() } } label: {
            Group {
                if phase == .saving { ProgressView().tint(.white) }
                else { Text(String(localized: "Save")).font(.headline) }
            }
            .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(ShiftPalette.accent.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.pressableCard)
        .disabled(phase == .saving)
    }

    // MARK: Actions

    private func addSkill() {
        let token = newSkill.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !token.isEmpty, !input.skills.contains(token) else { newSkill = ""; return }
        input.skills.append(token)
        newSkill = ""
    }

    private func load() async {
        guard let service else { phase = .form; return }
        let prefill = try? await service.fetchMyProfilePrefill()
        if let prefill, let vendor = prefill.vendor {
            isExisting = true
            termsAccepted = true   // they previously opted in
            input = VendorProfileInput(
                businessName: prefill.identity?.businessName ?? "",
                bio: prefill.identity?.bio ?? "",
                avatarURL: prefill.identity?.avatarURL,
                category: MarketplaceCategory.role(vendor.category),
                customCategoryLabel: VendorRole(rawValue: vendor.category) == nil ? vendor.category : "",
                skills: vendor.skills,
                serviceArea: vendor.serviceArea ?? "",
                latitude: vendor.latitude,
                longitude: vendor.longitude,
                serviceRadiusKm: vendor.serviceRadiusKm ?? 80,
                isListed: vendor.isListed
            )
            phase = .form
        } else {
            // New opt-in: seed category from default_role, gate on Terms.
            if let role = prefill?.defaultRole { input.category = role }
            phase = termsAccepted ? .form : .terms
        }
    }

    private func uploadAvatar(_ item: PhotosPickerItem) async {
        guard let service else { return }
        isUploadingAvatar = true
        defer { isUploadingAvatar = false }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        if let url = try? await service.uploadAvatar(data: data) {
            input.avatarURL = url.absoluteString
        }
    }

    private func save() async {
        guard let service else { return }
        let trimmedName = input.businessName.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.isListed, trimmedName.isEmpty {
            errorMessage = String(localized: "Add a business name before listing.")
            return
        }
        phase = .saving
        errorMessage = nil

        // Geocode the service area → lat/lng for radius search (best-effort; keep
        // existing coordinates if geocoding fails or the field is empty).
        let area = input.serviceArea.trimmingCharacters(in: .whitespacesAndNewlines)
        if !area.isEmpty, let coord = await Self.geocode(area) {
            input.latitude = coord.lat
            input.longitude = coord.lng
        }

        do {
            try await service.upsertMyVendorProfile(input)
            dismiss()
        } catch {
            errorMessage = String(localized: "Couldn't save your profile. Check your connection and try again.")
            phase = .form
        }
    }

    /// Address → coordinate via CLGeocoder (bridged async). The non-Sendable
    /// placemarks stay inside this function; only the Double pair is returned.
    private static func geocode(_ address: String) async -> (lat: Double, lng: Double)? {
        guard let placemarks = try? await CLGeocoder().geocodeAddressString(address),
              let location = placemarks.first?.location else { return nil }
        return (location.coordinate.latitude, location.coordinate.longitude)
    }
}
