import SwiftUI

/// Content-safety primitives required by App Store Review Guideline 1.2 (UGC):
/// in-app reporting of objectionable content and blocking of abusive
/// collaborators. Self-contained — reports are emailed to the monitored abuse
/// mailbox and blocks are stored locally so a blocked contact can't be
/// re-invited.
enum ContentSafety {
    /// Mailbox monitored for abuse / objectionable-content reports.
    static let abuseEmail = "abuse@shifttimeline.app"
}

// MARK: - Block list

/// Locally-persisted set of blocked contacts, keyed by normalized phone/email.
/// A blocked contact is removed from events and cannot be re-invited.
@MainActor
final class BlockedContactsStore {
    static let shared = BlockedContactsStore()

    private let defaultsKey = "contentSafety.blockedContacts"
    private let defaults = UserDefaults.standard

    private init() {}

    private var blocked: Set<String> {
        get { Set(defaults.stringArray(forKey: defaultsKey) ?? []) }
        set { defaults.set(Array(newValue), forKey: defaultsKey) }
    }

    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Whether either the phone or email is on the block list (empty fields ignored).
    func isBlocked(phone: String, email: String) -> Bool {
        let set = blocked
        let p = Self.normalize(phone)
        let e = Self.normalize(email)
        return (!p.isEmpty && set.contains(p)) || (!e.isEmpty && set.contains(e))
    }

    func block(phone: String, email: String) {
        var set = blocked
        let p = Self.normalize(phone)
        let e = Self.normalize(email)
        if !p.isEmpty { set.insert(p) }
        if !e.isEmpty { set.insert(e) }
        blocked = set
    }

    func unblock(phone: String, email: String) {
        var set = blocked
        let p = Self.normalize(phone)
        let e = Self.normalize(email)
        if !p.isEmpty { set.remove(p) }
        if !e.isEmpty { set.remove(e) }
        blocked = set
    }
}

// MARK: - Report sheet

/// In-app "Report a Concern" form. Collects a reason + optional details and
/// delivers the report to the monitored abuse mailbox. Reachable from Settings
/// and from the report action on collaborators / shared content.
struct ReportConcernSheet: View {

    /// Short description of what's being reported, e.g. "Collaborator: Acme Co."
    /// Empty for a general report from Settings.
    var context: String = ""

    @Environment(\.dismiss) private var dismiss
    @State private var reason: Reason = .objectionableContent
    @State private var details = ""
    @State private var isShowingMail = false
    @State private var showNoMailAlert = false

    enum Reason: String, CaseIterable, Identifiable {
        case objectionableContent
        case harassment
        case spam
        case impersonation
        case other

        var id: String { rawValue }

        var label: String {
            switch self {
            case .objectionableContent: String(localized: "Objectionable content")
            case .harassment: String(localized: "Harassment or abuse")
            case .spam: String(localized: "Spam")
            case .impersonation: String(localized: "Impersonation")
            case .other: String(localized: "Something else")
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if !context.isEmpty {
                    Section(String(localized: "Reporting")) {
                        Text(context).foregroundStyle(.secondary)
                    }
                }
                Section(String(localized: "Reason")) {
                    Picker(String(localized: "Reason"), selection: $reason) {
                        ForEach(Reason.allCases) { reason in
                            Text(reason.label).tag(reason)
                        }
                    }
                }
                Section(String(localized: "Details (optional)")) {
                    TextField(String(localized: "Describe the concern"), text: $details, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section {
                    Text(String(localized: "We review every report and act on it, typically within 24 hours."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(String(localized: "Report a Concern"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Submit")) { submit() }
                }
            }
            .sheet(isPresented: $isShowingMail) {
                MailComposeView(
                    recipient: ContentSafety.abuseEmail,
                    subject: String(localized: "SHIFT — Report a Concern"),
                    body: reportBody
                ) {
                    isShowingMail = false
                    dismiss()
                }
                .ignoresSafeArea()
            }
            .alert(String(localized: "Email Not Available"), isPresented: $showNoMailAlert) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: {
                Text(String(localized: "Please email \(ContentSafety.abuseEmail) to report this concern. We respond within 24 hours."))
            }
        }
    }

    private var reportBody: String {
        var lines = [String(localized: "Reason: \(reason.label)")]
        if !context.isEmpty { lines.append(String(localized: "Item: \(context)")) }
        if !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(String(localized: "Details: \(details)"))
        }
        return lines.joined(separator: "\n")
    }

    private func submit() {
        if MailComposeView.canSend {
            isShowingMail = true
        } else {
            showNoMailAlert = true
        }
    }
}
