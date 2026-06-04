import SwiftUI

/// Source of truth for the in-app Privacy Policy and Terms of Service.
///
/// The text is drafted in a conventional legal register and reflects what the
/// app actually does: local SwiftData storage, anonymous TelemetryDeck analytics,
/// venue coordinates sent to Apple WeatherKit and sunrise-sunset.org, microphone
/// voice memos, and App Store purchases. Update the constants below (entity,
/// contact, jurisdiction, effective date) and have the documents reviewed by
/// counsel before App Store submission. These documents are a starting point,
/// not legal advice.
enum LegalContent {

    // MARK: - Editable constants

    static let appName = "SHIFT"
    static let companyName = "Neel Software Solutions"
    static let contactEmail = "privacy@shift.app"
    static let governingLaw = "the State of New Jersey, United States"

    /// The "Effective Date" shown on both documents.
    static let effectiveDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 2
        return Calendar.current.date(from: components) ?? .now
    }()

    // MARK: - Privacy Policy

    static var privacyPolicy: LegalDocument {
        LegalDocument(
            title: String(localized: "Privacy Policy"),
            summary: String(localized: "This Privacy Policy describes how \(companyName) handles information in connection with the \(appName) application. Please read it carefully to understand our practices."),
            lastUpdated: effectiveDate,
            sections: [
                LegalSection(heading: "Introduction and Scope", blocks: [
                    .paragraph("This Privacy Policy (the **\"Policy\"**) applies to the \(appName) mobile application for iOS and watchOS (the **\"App\"**) provided by \(companyName) (**\"we,\" \"us,\"** or **\"our\"**). It explains what information the App processes, how that information is used, and the rights available to you. It does not apply to third-party services that maintain their own privacy policies, as described in the \"Third-Party Services\" section below."),
                    .paragraph("In this Policy, **\"Personal Information\"** means information that identifies, relates to, or could reasonably be linked to an identifiable individual. By using the App, you acknowledge that you have read and understood this Policy.")
                ]),
                LegalSection(heading: "Information You Provide", blocks: [
                    .paragraph("The App is designed so that the content you create remains under your control. You may provide the following information when you use the App:"),
                    .bullets([
                        "Event details, such as titles, dates, venue names, and notes;",
                        "Timeline data, such as blocks, durations, dependencies, and shift history;",
                        "Vendor contact details that you enter, such as names, roles, telephone numbers, and email addresses;",
                        "Venue selections that you search for and choose; and",
                        "Voice recordings that you optionally create and attach to a block."
                    ]),
                    .paragraph("This content is stored locally on your device and, where iCloud is enabled, synchronized to your private iCloud account. We do not receive or store this content on our own servers.")
                ]),
                LegalSection(heading: "Information Collected Automatically", blocks: [
                    .paragraph("To understand how the App is used and to improve its functionality, the App collects limited, anonymous usage information through TelemetryDeck, a privacy-focused analytics provider. This information is aggregated and is not used to identify you."),
                    .paragraph("Such information may include the frequency of feature usage (for example, creating an event, applying a timeline shift, or exporting a document), non-identifying event parameters (such as the magnitude of a shift), and general diagnostic information used to detect and resolve errors.")
                ]),
                LegalSection(heading: "Information We Do Not Collect", blocks: [
                    .paragraph("The App does not:"),
                    .bullets([
                        "Sell or rent Personal Information;",
                        "Collect advertising identifiers or engage in cross-application tracking;",
                        "Access your device's precise location in the background or track your movements;",
                        "Access your contacts, photo library, or calendar; or",
                        "Collect your name, email address, or telephone number for analytics purposes."
                    ])
                ]),
                LegalSection(heading: "How We Use Information", blocks: [
                    .paragraph("Information processed by the App is used to:"),
                    .bullets([
                        "Provide, operate, and maintain the features of the App;",
                        "Synchronize your data across your devices through iCloud;",
                        "Enable read-only sharing of timelines with recipients you designate;",
                        "Enrich timelines with sunset and weather information for venues you select;",
                        "Analyze aggregate, anonymous usage in order to improve the App; and",
                        "Comply with applicable legal obligations."
                    ])
                ]),
                LegalSection(heading: "Data Storage", blocks: [
                    .paragraph("Your event data is stored locally on your device using Apple SwiftData. It is not automatically uploaded to any third-party server. We do not have access to the contents of your local store.")
                ]),
                LegalSection(heading: "Location and Venue Information", blocks: [
                    .paragraph("The App does not access your device's GPS location and does not perform background location tracking. When you search for a venue, Apple MapKit returns location results from which you select the coordinates associated with your event."),
                    .paragraph("The selected coordinates, together with the relevant event date, are transmitted to Apple WeatherKit to obtain a weather forecast and to sunrise-sunset.org to calculate sunset and golden-hour times. Only coordinates and a date are transmitted; no Personal Information is included in these requests.")
                ]),
                LegalSection(heading: "Voice Recordings", blocks: [
                    .paragraph("If you choose to attach a voice memo to a timeline block, the App will request access to your device's microphone. Recordings are stored locally and, where iCloud is enabled, within your private iCloud account. Recordings are not transmitted to us or to any third party. You may delete recordings at any time and may revoke microphone access through your device settings.")
                ]),
                LegalSection(heading: "Third-Party Services", blocks: [
                    .paragraph("The App relies on the following third-party services, each of which processes information solely for the purpose indicated and in accordance with its own terms and privacy policy:"),
                    .bullets([
                        "Apple iCloud and CloudKit — storage and synchronization of your data;",
                        "Apple WeatherKit — weather forecasts for selected venues;",
                        "Apple MapKit — venue search and location results;",
                        "Apple App Store and StoreKit — processing of in-app purchases;",
                        "TelemetryDeck — anonymous, aggregated usage analytics; and",
                        "sunrise-sunset.org — calculation of sunset and golden-hour times."
                    ]),
                    .paragraph("We are not responsible for the privacy practices of these third parties and encourage you to review their respective policies.")
                ]),
                LegalSection(heading: "Disclosure of Information", blocks: [
                    .paragraph("We do not sell, rent, or trade Personal Information. We may disclose information only: (a) with your consent or at your direction, such as when you share a timeline; (b) to comply with applicable law, legal process, or a governmental request; or (c) to protect the rights, property, or safety of \(companyName), our users, or the public, as permitted by law.")
                ]),
                LegalSection(heading: "Data Retention", blocks: [
                    .paragraph("Because your content resides on your device and within your private iCloud account, it is retained until you delete it. Deleting the App removes its locally stored data from that device, and you may delete the App's iCloud data through your Apple ID settings. Aggregate, anonymous analytics cannot be associated with you and are retained only in de-identified form.")
                ]),
                LegalSection(heading: "Your Privacy Rights", blocks: [
                    .paragraph("Depending on your jurisdiction, you may have rights under data-protection laws such as the EU and UK General Data Protection Regulation (**\"GDPR\"**) and the California Consumer Privacy Act (**\"CCPA\"**), including the rights to access, correct, delete, and port your Personal Information, and to object to or restrict certain processing."),
                    .paragraph("Because your Personal Information is stored within your own iCloud account, you may exercise many of these rights directly through Apple's services. We do not sell Personal Information, and therefore no opt-out of sale is required. To make a request or ask a question regarding your rights, contact us using the details in the \"Contact Us\" section below.")
                ]),
                LegalSection(heading: "International Transfers and Security", blocks: [
                    .paragraph("The third-party services described above are operated by providers that may process information in countries other than your own. Those providers maintain their own safeguards for international data transfers."),
                    .paragraph("We take reasonable measures to support the security of information processed by the App, and iCloud data is encrypted by Apple in transit and at rest. However, no method of transmission or storage is completely secure, and we cannot guarantee absolute security.")
                ]),
                LegalSection(heading: "Children's Privacy", blocks: [
                    .paragraph("The App is intended for use by event professionals and is not directed to children under the age of 13, or the equivalent minimum age in your jurisdiction. We do not knowingly collect Personal Information from children. If you believe that a child has provided Personal Information, please contact us so that we may take appropriate action.")
                ]),
                LegalSection(heading: "Changes to This Privacy Policy", blocks: [
                    .paragraph("We may update this Policy from time to time. When we do, we will revise the Effective Date shown above and, where the changes are material, provide notice within the App. Your continued use of the App after an update takes effect constitutes your acceptance of the revised Policy.")
                ]),
                LegalSection(heading: "Contact Us", blocks: [
                    .paragraph("If you have questions or requests regarding this Policy, you may contact \(companyName) at \(contactEmail).")
                ])
            ]
        )
    }

    // MARK: - Terms of Service

    static var termsOfService: LegalDocument {
        LegalDocument(
            title: String(localized: "Terms of Service"),
            summary: String(localized: "PLEASE READ THESE TERMS OF SERVICE CAREFULLY. BY DOWNLOADING, ACCESSING, OR USING THE \(appName.uppercased()) APPLICATION, YOU AGREE TO BE BOUND BY THESE TERMS. IF YOU DO NOT AGREE, DO NOT USE THE APP."),
            lastUpdated: effectiveDate,
            sections: [
                LegalSection(heading: "Agreement to Terms", blocks: [
                    .paragraph("These Terms of Service (the **\"Terms\"**) constitute a legally binding agreement between you and \(companyName) (**\"we,\" \"us,\"** or **\"our\"**) governing your access to and use of the \(appName) mobile application for iOS and watchOS (the **\"App\"**). By downloading, accessing, or using the App, you agree to these Terms and to our Privacy Policy, which is incorporated herein by reference. If you do not agree, you must not use the App.")
                ]),
                LegalSection(heading: "Eligibility", blocks: [
                    .paragraph("You must be at least the age of majority in your jurisdiction, and otherwise capable of forming a binding contract, to use the App. By using the App, you represent and warrant that you meet these requirements and that your use complies with all applicable laws and with the terms imposed by Apple Inc. in connection with the App Store.")
                ]),
                LegalSection(heading: "License to Use the App", blocks: [
                    .paragraph("Subject to your compliance with these Terms, we grant you a limited, personal, non-exclusive, non-transferable, non-sublicensable, and revocable license to download and use the App on Apple-branded devices that you own or control, for your personal or internal business purposes. All rights not expressly granted to you are reserved by us.")
                ]),
                LegalSection(heading: "iCloud and Device Requirements", blocks: [
                    .paragraph("Certain features, including synchronization and sharing, require a device signed in to iCloud and an active network connection, and depend on services provided by Apple. You are responsible for your device, your Apple ID, and the security of your credentials. We do not guarantee the availability, reliability, or performance of third-party services on which the App depends.")
                ]),
                LegalSection(heading: "Subscriptions and Payment", blocks: [
                    .paragraph("The App offers an optional paid subscription (**\"SHIFT Pro\"**), available as monthly, annual, or one-time lifetime purchases through the Apple App Store. The following terms apply:"),
                    .bullets([
                        "Payment is charged to your Apple ID account upon confirmation of purchase;",
                        "Monthly and annual subscriptions automatically renew unless cancelled at least twenty-four (24) hours before the end of the then-current period;",
                        "You may manage or cancel a subscription through your App Store account settings;",
                        "A lifetime purchase is a single, non-recurring payment; and",
                        "You may restore an eligible purchase on another device using the same Apple ID."
                    ]),
                    .paragraph("Prices and offerings may change; any change will apply only to billing periods following the change. All payments are processed by Apple, and refunds are handled by Apple in accordance with the App Store terms. We do not receive or store your payment-card details.")
                ]),
                LegalSection(heading: "Free and Pro Tiers", blocks: [
                    .paragraph("The App provides a free tier with limited functionality, including a limited number of active events and a cap on the number of blocks per event, and a paid tier that removes those limitations and unlocks additional features such as vendor sharing, the watchOS companion, widgets and Live Activities, templates, and document export. The specific limits applicable to each tier are presented within the App and may be modified over time.")
                ]),
                LegalSection(heading: "User Content and Responsibilities", blocks: [
                    .paragraph("You retain all rights in the timelines, notes, contact details, and other content you create or input in the App (**\"User Content\"**). Because User Content is stored on your device and within your private iCloud account, we do not access it and acquire no rights in it."),
                    .paragraph("You are solely responsible for the accuracy of your User Content and for ensuring that you have all necessary rights and permissions to store and share any third-party information, including vendor contact details. You agree to use such information only for the legitimate coordination of your events and in compliance with applicable law.")
                ]),
                LegalSection(heading: "Sharing and Collaboration", blocks: [
                    .paragraph("The App allows you to share a timeline with recipients you designate, on a read-only basis. You are responsible for selecting recipients and for the consequences of sharing, and you may revoke access to a shared timeline at any time.")
                ]),
                LegalSection(heading: "Acceptable Use", blocks: [
                    .paragraph("You agree not to:"),
                    .bullets([
                        "Use the App in violation of any applicable law or the rights of any third party;",
                        "Reverse engineer, decompile, disassemble, or otherwise attempt to derive the source code of the App, except to the extent this restriction is prohibited by applicable law;",
                        "Interfere with or disrupt the integrity or performance of the App or the services on which it relies, or attempt to gain unauthorized access to them; or",
                        "Misuse contact information or other data stored within the App."
                    ])
                ]),
                LegalSection(heading: "Intellectual Property", blocks: [
                    .paragraph("The App, including its underlying technology and the \(appName) Ripple Engine, together with all associated designs, text, graphics, and trademarks, is owned by \(companyName) and is protected by intellectual-property laws. These Terms do not grant you any right, title, or interest in the App other than the limited license expressly set forth herein.")
                ]),
                LegalSection(heading: "Third-Party Services", blocks: [
                    .paragraph("The App integrates with services provided by Apple (including iCloud, CloudKit, WeatherKit, MapKit, and the App Store) and by other third parties (including TelemetryDeck and sunrise-sunset.org). Your use of those services may be subject to additional terms imposed by the respective providers. We are not responsible for third-party services or their availability.")
                ]),
                LegalSection(heading: "Disclaimer of Warranties", blocks: [
                    .paragraph("THE APP IS PROVIDED \"AS IS\" AND \"AS AVAILABLE,\" WITHOUT WARRANTIES OF ANY KIND, WHETHER EXPRESS, IMPLIED, OR STATUTORY, INCLUDING WITHOUT LIMITATION THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE, AND NON-INFRINGEMENT. WE DO NOT WARRANT THAT THE APP WILL BE UNINTERRUPTED, TIMELY, SECURE, OR ERROR-FREE, OR THAT DATA WILL SYNCHRONIZE WITHOUT DELAY OR LOSS."),
                    .paragraph("Sunset, golden-hour, weather, and travel-time information is provided by third parties for convenience only, may be inaccurate or unavailable, and must not be relied upon for time-critical or safety-related decisions. The App is a planning aid and does not guarantee any outcome; you remain responsible for exercising your own professional judgment.")
                ]),
                LegalSection(heading: "Limitation of Liability", blocks: [
                    .paragraph("TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, IN NO EVENT WILL \(companyName.uppercased()) BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR EXEMPLARY DAMAGES, OR FOR ANY LOSS OF PROFITS, DATA, GOODWILL, OR BUSINESS, ARISING OUT OF OR RELATING TO YOUR USE OF OR INABILITY TO USE THE APP, WHETHER BASED ON WARRANTY, CONTRACT, TORT, OR ANY OTHER LEGAL THEORY, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGES."),
                    .paragraph("TO THE MAXIMUM EXTENT PERMITTED BY LAW, OUR TOTAL AGGREGATE LIABILITY FOR ALL CLAIMS RELATING TO THE APP WILL NOT EXCEED THE GREATER OF THE AMOUNT YOU PAID FOR THE APP IN THE TWELVE (12) MONTHS PRECEDING THE CLAIM OR FIVE U.S. DOLLARS (US$5.00). SOME JURISDICTIONS DO NOT ALLOW CERTAIN LIMITATIONS OF LIABILITY, SO SOME OF THE ABOVE LIMITATIONS MAY NOT APPLY TO YOU.")
                ]),
                LegalSection(heading: "Indemnification", blocks: [
                    .paragraph("You agree to indemnify, defend, and hold harmless \(companyName) from and against any claims, liabilities, damages, losses, and expenses, including reasonable legal fees, arising out of or in any way connected with your User Content, your use or misuse of the App, or your violation of these Terms or of applicable law.")
                ]),
                LegalSection(heading: "Termination", blocks: [
                    .paragraph("You may stop using the App at any time by deleting it from your devices. We may suspend or terminate your access to the App, in whole or in part, if you materially breach these Terms or use the App in a manner that may cause harm. Provisions that by their nature should survive termination, including those concerning intellectual property, disclaimers, limitation of liability, and indemnification, will survive.")
                ]),
                LegalSection(heading: "Governing Law and Dispute Resolution", blocks: [
                    .paragraph("These Terms are governed by the laws of \(governingLaw), without regard to its conflict-of-laws principles, except to the extent that mandatory consumer-protection laws of your place of residence apply. Before initiating any formal proceeding, you agree to first contact us and attempt in good faith to resolve the dispute informally. Any dispute that cannot be resolved informally will be subject to the exclusive jurisdiction of the competent courts located in \(governingLaw), to the extent permitted by applicable law.")
                ]),
                LegalSection(heading: "Changes to These Terms", blocks: [
                    .paragraph("We may modify these Terms from time to time. When we do, we will revise the Effective Date shown above and, where the changes are material, provide notice within the App. Your continued use of the App after the changes take effect constitutes your acceptance of the revised Terms.")
                ]),
                LegalSection(heading: "Miscellaneous", blocks: [
                    .paragraph("These Terms, together with the Privacy Policy, constitute the entire agreement between you and \(companyName) regarding the App and supersede any prior agreements. If any provision is held to be unenforceable, that provision will be limited or severed to the minimum extent necessary, and the remaining provisions will remain in full force and effect. Our failure to enforce any provision is not a waiver of that provision. You may not assign these Terms without our prior written consent; we may assign them in connection with a merger, acquisition, or sale of assets.")
                ]),
                LegalSection(heading: "Contact Us", blocks: [
                    .paragraph("Questions regarding these Terms may be directed to \(companyName) at \(contactEmail).")
                ])
            ]
        )
    }
}
