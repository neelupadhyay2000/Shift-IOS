import SwiftUI

/// Star rating + text composer for reviewing a vendor you worked with. Presented
/// from the post-event report / completed event ("Review your vendors"). One
/// review per vendor per event: on open it loads any existing review by the
/// signed-in reviewer and switches to edit mode (with a Remove action).
struct ReviewComposerView: View {

    let eventID: UUID
    let vendorProfileID: UUID
    let vendorName: String
    /// Called after a successful submit / edit / remove so the host can refresh.
    var onComplete: (() -> Void)?

    @Environment(\.vendorReviewService) private var service
    @Environment(\.dismiss) private var dismiss

    @State private var rating = 0
    @State private var reviewText = ""
    @State private var existing: VendorReviewRowDTO?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let maxBody = 2000

    private var isEditing: Bool { existing != nil }
    private var canSave: Bool { rating > 0 && !isSaving && service != nil }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    form
                }
            }
            .background { ProBackground() }
            .navigationTitle(isEditing ? String(localized: "Edit Review") : String(localized: "Review Vendor"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? String(localized: "Save") : String(localized: "Submit")) {
                        Task { await save() }
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier(AccessibilityID.Marketplace.reviewSubmitButton)
                }
            }
            .task { await load() }
        }
    }

    // MARK: Form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "How was working with \(vendorName)?"))
                        .font(.headline)
                    starPicker
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Review")).microLabel()
                    TextEditor(text: $reviewText)
                        .frame(minHeight: 140)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(ShiftPalette.soft(ShiftPalette.neutral), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onChange(of: reviewText) { _, newValue in
                            if newValue.count > maxBody { reviewText = String(newValue.prefix(maxBody)) }
                        }
                        .accessibilityIdentifier(AccessibilityID.Marketplace.reviewBodyField)
                    Text("\(reviewText.count)/\(maxBody)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if isEditing {
                    Button(role: .destructive) {
                        Task { await remove() }
                    } label: {
                        Label(String(localized: "Remove Review"), systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSaving)
                }
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
    }

    private var starPicker: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    rating = star
                } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.system(size: 30))
                        .foregroundStyle(star <= rating ? ShiftPalette.accent : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "\(star) star\(star == 1 ? "" : "s")"))
            }
        }
        .accessibilityIdentifier(AccessibilityID.Marketplace.reviewStarPicker)
    }

    // MARK: Actions

    private func load() async {
        guard let service else { isLoading = false; return }
        defer { isLoading = false }
        if let row = try? await service.myReview(eventID: eventID, vendorProfileID: vendorProfileID) {
            existing = row
            rating = row.rating
            reviewText = row.body
        }
    }

    private func save() async {
        guard let service, rating > 0 else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            if let existing {
                _ = try await service.updateReview(reviewID: existing.id, rating: rating, body: reviewText)
            } else {
                _ = try await service.submitReview(
                    eventID: eventID, vendorProfileID: vendorProfileID, rating: rating, body: reviewText
                )
            }
            AnalyticsService.send(.marketplaceReviewSubmitted, parameters: ["rating": String(rating)])
            Haptics.success()
            onComplete?()
            dismiss()
        } catch {
            errorMessage = String(localized: "Couldn't save your review. Check your connection and try again.")
        }
    }

    private func remove() async {
        guard let service, let existing else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await service.deleteReview(reviewID: existing.id)
            onComplete?()
            dismiss()
        } catch {
            errorMessage = String(localized: "Couldn't remove your review. Please try again.")
        }
    }
}
