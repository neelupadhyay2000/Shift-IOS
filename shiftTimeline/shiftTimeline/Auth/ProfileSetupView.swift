import Models
import SwiftUI

/// Forced profile creation (E19), shown after OTP + passcode for a new account
/// until `profiles.onboarded` is true. Step 1 picks an account type; step 2 is the
/// matching form. On success it writes the profile and refreshes the auth profile,
/// which flips the gate and reveals the app.
struct ProfileSetupView: View {

    @Environment(SupabaseAuthService.self) private var authService

    @State private var selection: AccountType?

    var body: some View {
        ZStack {
            SignInBrandBackground().ignoresSafeArea()
            Group {
                switch selection {
                case .none:
                    RoleChooser { selection = $0 }
                case .planner:
                    PlannerSetupForm(onBack: { selection = nil }, onComplete: complete)
                case .vendor:
                    VendorSetupForm(onBack: { selection = nil }, onComplete: complete)
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        }
        .animation(.easeInOut(duration: 0.25), value: selection)
        .accessibilityIdentifier(AccessibilityID.Onboarding.root)
    }

    /// Shared completion: each form does its own write, then we refresh the
    /// cached profile so `needsOnboarding` flips false and the gate dismisses.
    private func complete() async {
        await authService.refreshProfile()
    }
}

// MARK: - Account type

enum AccountType: Equatable {
    case planner
    case vendor
}

// MARK: - Role chooser

private struct RoleChooser: View {
    let onPick: (AccountType) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text(String(localized: "Create your profile"))
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                Text(String(localized: "How will you use Shift?"))
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .multilineTextAlignment(.center)
            .padding(.top, 60)

            Spacer()

            VStack(spacing: 16) {
                roleCard(
                    type: .planner,
                    icon: "calendar.badge.clock",
                    title: String(localized: "I'm a planner"),
                    blurb: String(localized: "Plan weddings, parties and corporate events. Build timelines and run the day-of.")
                )
                .accessibilityIdentifier(AccessibilityID.Onboarding.plannerCard)

                roleCard(
                    type: .vendor,
                    icon: "storefront.fill",
                    title: String(localized: "I'm a vendor"),
                    blurb: String(localized: "Offer your services — get discovered in the marketplace and booked for events.")
                )
                .accessibilityIdentifier(AccessibilityID.Onboarding.vendorCard)
            }
            .padding(.horizontal, 24)

            Text(String(localized: "You can add the other role later in Settings."))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 20)

            Spacer()
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private func roleCard(type: AccountType, icon: String, title: String, blurb: String) -> some View {
        Button { onPick(type) } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundStyle(ShiftPalette.accent)
                    .frame(width: 56, height: 56)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(.white)
                    Text(blurb).font(.caption).foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.6))
            }
            .padding(18)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
    }
}

// MARK: - Onboarding form scaffold

/// Shared chrome for the two forms: a header with a back button + the brand wash,
/// a scrollable body, and a sticky primary button with a saving/error state.
private struct OnboardingFormScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    let actionTitle: String
    let canSubmit: Bool
    let onBack: () -> Void
    let onSubmit: () async -> Void
    @ViewBuilder var content: () -> Content

    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { onBack() } label: {
                    Image(systemName: "chevron.left").font(.headline).foregroundStyle(.white)
                }
                .disabled(isSaving)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title).font(.title.weight(.bold)).foregroundStyle(.white)
                        Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.85))
                    }
                    content()
                }
                .padding(20)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }

            submitButton
        }
    }

    private var submitButton: some View {
        Button {
            Task {
                isSaving = true
                defer { isSaving = false }
                await onSubmit()
            }
        } label: {
            Group {
                if isSaving { ProgressView().tint(ShiftPalette.accent) }
                else { Text(actionTitle).font(.headline) }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .foregroundStyle(ShiftPalette.accent)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(canSubmit ? 1 : 0.5)
        }
        .buttonStyle(.pressableCard)
        .disabled(!canSubmit || isSaving)
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .frame(maxWidth: 560).frame(maxWidth: .infinity)
        .accessibilityIdentifier(AccessibilityID.Onboarding.submitButton)
    }
}

// MARK: - Planner form

private struct PlannerSetupForm: View {
    let onBack: () -> Void
    let onComplete: () async -> Void

    @Environment(\.onboardingService) private var onboarding
    @State private var displayName = ""
    @State private var focus = ""
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && onboarding != nil
    }

    var body: some View {
        OnboardingFormScaffold(
            title: String(localized: "About you"),
            subtitle: String(localized: "This is how vendors and collaborators will see you."),
            actionTitle: String(localized: "Continue"),
            canSubmit: canSubmit,
            onBack: onBack,
            onSubmit: submit
        ) {
            field(String(localized: "Your name"), text: $displayName, placeholder: String(localized: "e.g. Neel Upadhyay"))
                .accessibilityIdentifier(AccessibilityID.Onboarding.plannerNameField)
            field(String(localized: "What do you plan? (optional)"), text: $focus, placeholder: String(localized: "e.g. Weddings & corporate events"))
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.white).opacity(0.9)
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
            TextField("", text: text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.5)))
                .foregroundStyle(.white)
                .padding(14)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func submit() async {
        guard let onboarding else { return }
        do {
            try await onboarding.completePlanner(
                displayName: displayName,
                focus: focus.isEmpty ? nil : focus
            )
            AnalyticsService.send(.onboardingCompleted, parameters: ["type": "planner"])
            await onComplete()
        } catch {
            errorMessage = String(localized: "Couldn't save your profile. Check your connection and try again.")
        }
    }
}

// MARK: - Vendor form

private struct VendorSetupForm: View {
    let onBack: () -> Void
    let onComplete: () async -> Void

    @Environment(\.onboardingService) private var onboarding
    @State private var businessName = ""
    @State private var category: VendorRole = .photographer
    @State private var customCategory = ""
    @State private var serviceArea = ""
    @State private var bio = ""
    @State private var skillInput = ""
    @State private var skills: [String] = []
    @State private var isListed = true
    @State private var errorMessage: String?

    private let categories: [VendorRole] = [.photographer, .dj, .caterer, .florist, .custom]

    private var canSubmit: Bool {
        let nameOK = !businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let categoryOK = category != .custom || !customCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return nameOK && categoryOK && onboarding != nil
    }

    var body: some View {
        OnboardingFormScaffold(
            title: String(localized: "Your business"),
            subtitle: String(localized: "Create your marketplace profile so planners can find and book you."),
            actionTitle: String(localized: "Create profile"),
            canSubmit: canSubmit,
            onBack: onBack,
            onSubmit: submit
        ) {
            field(String(localized: "Business name"), text: $businessName, placeholder: String(localized: "e.g. Golden Hour Studio"))
                .accessibilityIdentifier(AccessibilityID.Onboarding.vendorNameField)
            categoryPicker
            if category == .custom {
                field(String(localized: "Your service type"), text: $customCategory, placeholder: String(localized: "e.g. Photo booth"))
            }
            field(String(localized: "Service area (optional)"), text: $serviceArea, placeholder: String(localized: "e.g. San Francisco Bay Area"))
            skillsField
            field(String(localized: "Short bio (optional)"), text: $bio, placeholder: String(localized: "What makes your work great?"))
            Toggle(isOn: $isListed) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "List me in the marketplace")).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Text(String(localized: "You can change this anytime.")).font(.caption2).foregroundStyle(.white.opacity(0.7))
                }
            }
            .tint(.white)
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.white).opacity(0.9)
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
            TextField("", text: text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.5)))
                .foregroundStyle(.white)
                .padding(14)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Category")).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { role in
                        let isSelected = category == role
                        Button { category = role } label: {
                            Text(role.displayName)
                                .font(.subheadline.weight(isSelected ? .semibold : .medium))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .foregroundStyle(isSelected ? ShiftPalette.accent : .white)
                                .background(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.12)), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var skillsField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Skills (optional)")).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
            HStack {
                TextField("", text: $skillInput, prompt: Text(String(localized: "Add a skill")).foregroundColor(.white.opacity(0.5)))
                    .foregroundStyle(.white)
                    .onSubmit(addSkill)
                Button(action: addSkill) { Image(systemName: "plus.circle.fill").foregroundStyle(.white) }
                    .disabled(skillInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(14)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if !skills.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(skills, id: \.self) { skill in
                            HStack(spacing: 4) {
                                Text(skill.capitalized).font(.caption)
                                Button { skills.removeAll { $0 == skill } } label: { Image(systemName: "xmark.circle.fill") }
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.white.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
        }
    }

    private func addSkill() {
        let trimmed = skillInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !skills.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        skills.append(trimmed)
        skillInput = ""
    }

    private func submit() async {
        guard let onboarding else { return }
        let input = VendorProfileInput(
            businessName: businessName,
            bio: bio,
            category: category,
            customCategoryLabel: customCategory,
            skills: skills,
            serviceArea: serviceArea,
            isListed: isListed
        )
        do {
            try await onboarding.completeVendor(input)
            AnalyticsService.send(.onboardingCompleted, parameters: ["type": "vendor"])
            await onComplete()
        } catch {
            errorMessage = String(localized: "Couldn't create your profile. Check your connection and try again.")
        }
    }
}
