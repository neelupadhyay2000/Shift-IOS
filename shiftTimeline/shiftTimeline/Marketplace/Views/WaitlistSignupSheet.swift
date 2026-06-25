import Models
import SwiftUI

/// Waitlist signup sheet, presented from the teaser CTA.
///
/// Online-only: loads the user's existing entry on appear so reopening shows
/// current values and edits idempotently (upsert on `profile_id`), submits via
/// ``WaitlistServing``, and
/// surfaces loading / error states inline. A successful submit flips
/// `MarketplaceDefaultsKey.waitlistJoined` so the teaser shows its joined card.
///
/// Styling: ProBackground canvas, selectable icon cards for the
/// interest role (the VendorFormSheet grid pattern), role-coloured capsule
/// chips for the category, and a proCard region field. No stock Form.
struct WaitlistSignupSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.waitlistService) private var waitlistService
    @AppStorage(MarketplaceDefaultsKey.waitlistJoined) private var hasJoinedWaitlist = false

    private enum Phase {
        case loading
        case form
        case submitting
        case confirmed
    }

    @State private var phase: Phase = .loading
    @State private var interestRole: WaitlistInterestRole = .vendor
    @State private var category: VendorRole = .photographer
    @State private var customCategory = ""
    @State private var region = ""
    @State private var isExistingEntry = false
    @State private var errorMessage: String?
    @FocusState private var isRegionFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .form, .submitting:
                    signupForm
                case .confirmed:
                    confirmedState
                }
            }
            .background { ProBackground() }
            .navigationTitle(String(localized: "Marketplace waitlist"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if phase != .confirmed {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel")) { dismiss() }
                            .accessibilityIdentifier(AccessibilityID.Waitlist.cancelButton)
                    }
                }
            }
            .task { await loadCurrentEntry() }
        }
    }

    // MARK: Form

    private var signupForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(String(localized: "Tell us where you fit — we'll line up the right matches for launch."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "I'm here as"))
                        .microLabel()
                    interestRoleGrid
                }

                // Category only applies to signups that include vendor work.
                if interestRole != .planner {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(localized: "Category"))
                            .microLabel()
                        categoryChips

                        // Free-text vendor type for the Custom category — what
                        // we'll match on when the marketplace opens.
                        if category == .custom {
                            TextField(
                                String(localized: "Vendor type"),
                                text: $customCategory,
                                prompt: Text(String(localized: "e.g. Videographer"))
                            )
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .proCard(padding: 14)
                            .accessibilityLabel(String(localized: "Custom vendor type"))
                            .accessibilityIdentifier(AccessibilityID.Waitlist.customCategoryField)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .animation(.easeInOut(duration: 0.2), value: category)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "Region"))
                        .microLabel()
                    TextField(
                        String(localized: "Region"),
                        text: $region,
                        prompt: Text(String(localized: "Toronto, ON"))
                    )
                    .textInputAutocapitalization(.words)
                    .focused($isRegionFocused)
                    .submitLabel(.done)
                    .proCard(padding: 14)
                    .accessibilityIdentifier(AccessibilityID.Waitlist.regionField)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                submitButton
            }
            .padding(20)
            // Readable column on iPad / wide layouts; full width on iPhone.
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.2), value: interestRole)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Interest role cards

    private var interestRoleGrid: some View {
        HStack(spacing: 10) {
            ForEach(WaitlistInterestRole.allCases, id: \.self) { role in
                let isSelected = interestRole == role

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        interestRole = role
                    }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: role.systemImage)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : ShiftPalette.accent)
                            .frame(width: 44, height: 44)
                            .background(
                                isSelected ? ShiftPalette.accent : Color.clear,
                                in: RoundedRectangle(cornerRadius: ShiftDesign.iconRadius, style: .continuous)
                            )
                            .background(
                                isSelected ? Color.clear : ShiftPalette.soft(ShiftPalette.accent),
                                in: RoundedRectangle(cornerRadius: ShiftDesign.iconRadius, style: .continuous)
                            )
                            .symbolEffect(.bounce, value: isSelected)

                        Text(role.displayName)
                            .font(.caption2)
                            .fontWeight(isSelected ? .bold : .medium)
                            .foregroundStyle(isSelected ? ShiftPalette.accent : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        isSelected ? ShiftPalette.accent.opacity(0.06) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isSelected ? ShiftPalette.accent.opacity(0.3) : Color.clear,
                                lineWidth: 1.5
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityIdentifier(AccessibilityID.Waitlist.rolePicker)
    }

    // MARK: Category chips

    private var categoryChips: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
            ForEach(VendorRole.allCases, id: \.self) { role in
                let roleColor = ShiftDesign.roleColor(for: role)
                let isSelected = category == role

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        category = role
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: role.systemImage)
                            .font(.caption)
                        Text(role.displayName)
                            .font(.caption.weight(isSelected ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(isSelected ? .white : roleColor)
                    .background(
                        isSelected ? roleColor : ShiftPalette.soft(roleColor),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule().strokeBorder(
                            isSelected ? Color.clear : roleColor.opacity(0.25),
                            lineWidth: 1
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityIdentifier(AccessibilityID.Waitlist.categoryPicker)
    }

    // MARK: Submit button

    private var submitButton: some View {
        Button {
            isRegionFocused = false
            Task { await submit() }
        } label: {
            Group {
                if phase == .submitting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(isExistingEntry
                        ? String(localized: "Save changes")
                        : String(localized: "Join the waitlist"))
                        .font(.headline)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(ShiftPalette.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.pressableCard)
        .disabled(phase == .submitting)
        .accessibilityIdentifier(AccessibilityID.Waitlist.submitButton)
    }

    // MARK: Confirmed

    private var confirmedState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(ShiftPalette.soft(ShiftPalette.live))
                    .frame(width: 96, height: 96)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(ShiftPalette.live)
            }
            Text(String(localized: "You're on the list — we'll notify you at launch."))
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                dismiss()
            } label: {
                Text(String(localized: "Done"))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        ShiftPalette.accent,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
            }
            .buttonStyle(.pressableCard)
            .padding(.top, 8)
        }
        .padding(24)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Waitlist.confirmedState)
    }

    // MARK: Actions

    /// Prefills the form from the server row so editing is idempotent, and
    /// reconciles the local joined flag with the server's truth.
    private func loadCurrentEntry() async {
        guard let waitlistService else {
            phase = .form
            return
        }
        do {
            if let entry = try await waitlistService.currentEntry() {
                interestRole = WaitlistInterestRole(rawValue: entry.interestRole) ?? .vendor
                // An unrecognized category string is a user-entered custom
                // vendor type (mirror of the upsert payload projection).
                if let storedCategory = entry.category {
                    if let vendorRole = VendorRole(rawValue: storedCategory) {
                        category = vendorRole
                        customCategory = ""
                    } else {
                        category = .custom
                        customCategory = storedCategory
                    }
                }
                region = entry.region
                isExistingEntry = true
                hasJoinedWaitlist = true
            } else {
                hasJoinedWaitlist = false
            }
            phase = .form
        } catch {
            // Online-only feature: let the user fill the form anyway — the
            // submit path surfaces its own error if the network is still down.
            errorMessage = String(localized: "Couldn't load your waitlist details.")
            phase = .form
        }
    }

    private func submit() async {
        guard let waitlistService else {
            errorMessage = String(localized: "The waitlist isn't available right now. Please try again later.")
            return
        }
        phase = .submitting
        errorMessage = nil
        do {
            let vendorCategory: VendorRole? = interestRole == .planner ? nil : category
            try await waitlistService.upsert(
                role: interestRole,
                category: vendorCategory,
                customCategoryLabel: customCategory,
                region: region.trimmingCharacters(in: .whitespaces)
            )
            // Demand measurement — aggregate dimensions only, no
            // PII: the free-text region and custom vendor type never leave the
            // waitlist table (analytics always sees the enum raw value).
            AnalyticsService.send(.marketplaceWaitlistJoined, parameters: [
                "role": interestRole.rawValue,
                "category": vendorCategory?.rawValue ?? "none"
            ])
            hasJoinedWaitlist = true
            isExistingEntry = true
            phase = .confirmed
        } catch {
            errorMessage = String(localized: "Couldn't reach the server. Check your connection and try again.")
            phase = .form
        }
    }
}

// MARK: - WaitlistInterestRole Display

extension WaitlistInterestRole {
    var displayName: String {
        switch self {
        case .vendor: String(localized: "I'm a vendor")
        case .planner: String(localized: "I'm a planner")
        case .both: String(localized: "Both")
        }
    }

    var systemImage: String {
        switch self {
        case .vendor: "storefront.fill"
        case .planner: "clipboard.fill"
        case .both: "person.2.fill"
        }
    }
}

// MARK: - Previews

/// In-memory fake for previews.
private struct PreviewWaitlistService: WaitlistServing {
    var existingEntry: WaitlistEntryDTO?
    var failsOnSubmit = false

    func currentEntry() async throws -> WaitlistEntryDTO? { existingEntry }

    @discardableResult
    func upsert(
        role: WaitlistInterestRole,
        category: VendorRole?,
        customCategoryLabel: String,
        region: String
    ) async throws -> WaitlistEntryDTO {
        if failsOnSubmit { throw URLError(.notConnectedToInternet) }
        return WaitlistEntryDTO(
            profileID: UUID(),
            interestRole: role.rawValue,
            category: category?.rawValue,
            region: region
        )
    }
}

#Preview("New signup") {
    WaitlistSignupSheet()
        .environment(\.waitlistService, PreviewWaitlistService())
}

#Preview("Editing existing entry") {
    WaitlistSignupSheet()
        .environment(\.waitlistService, PreviewWaitlistService(
            existingEntry: WaitlistEntryDTO(
                profileID: UUID(),
                interestRole: "vendor",
                category: "dj",
                region: "Toronto, ON"
            )
        ))
}

#Preview("Submit fails — dark") {
    WaitlistSignupSheet()
        .environment(\.waitlistService, PreviewWaitlistService(failsOnSubmit: true))
        .preferredColorScheme(.dark)
}
