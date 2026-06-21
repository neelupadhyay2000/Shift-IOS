import Foundation

/// Centralised, namespaced accessibility identifier strings.
///
/// **Single source of truth** for the string values stamped on SwiftUI views
/// via `.accessibilityIdentifier(_:)`. An identical copy of this file lives in
/// `shiftTimelineUITests/Helpers/AccessibilityID.swift` so the test target can
/// reference the same constants without importing the app module.
///
/// Naming convention: `<screen>.<element_role>` — lowercase, dot-separated.
/// Never include spaces or special characters; these are machine identifiers, not
/// human-readable labels (use `.accessibilityLabel` for that).
enum AccessibilityID {

    // MARK: - Tab bar

    enum Tab {
        static let events      = "tab.events"
        static let marketplace = "tab.marketplace"
        static let templates   = "tab.templates"
        static let settings    = "tab.settings"
    }

    // MARK: - Event Roster (EventRosterView)

    enum Roster {
        static let addEventButton    = "roster.add_event_button"
        static let statusFilter      = "roster.status_filter"
        static let eventList         = "roster.event_list"
        static let createEventButton = "roster.create_event_button"
        static let demoEventButton   = "roster.demo_event_button"
    }

    // MARK: - Event Creation (CreateEventSheet)

    enum EventCreation {
        static let titleField   = "event_creation.title_field"
        static let datePicker   = "event_creation.date_picker"
        static let cancelButton = "event_creation.cancel_button"
        static let createButton = "event_creation.create_button"
    }

    // MARK: - Event Detail (EventDetailView)

    enum EventDetail {
        static let goLiveButton   = "event_detail.go_live_button"
        static let timelineButton = "event_detail.timeline_button"
        static let vendorsButton  = "event_detail.vendors_button"
        static let shareButton    = "event_detail.share_button"
    }

    // MARK: - Timeline Builder (TimelineBuilderView)

    enum Timeline {
        static let addBlockButton = "timeline.add_block_button"
        static let blockList      = "timeline.block_list"
        static let trackTabBar    = "timeline.track_tab_bar"
    }

    // MARK: - Block Inspector (BlockInspectorView)

    enum Inspector {
        static let titleField    = "inspector.title_field"
        static let durationField = "inspector.duration_field"
        static let saveButton    = "inspector.save_button"
        static let cancelButton  = "inspector.cancel_button"
        static let deleteButton  = "inspector.delete_button"
    }

    // MARK: - Live Dashboard (LiveDashboardView)

    enum Live {
        static let activeBlockHero     = "live.active_block_hero"
        static let slideToAdvance      = "live.slide_to_advance"
        static let exitLiveButton      = "live.exit_live_button"
        static let shiftTimelineButton = "live.shift_timeline_button"
        static let overtimeNudge       = "live.overtime_nudge"
        static let overtimeShiftButton = "live.overtime_shift_button"
    }

    // MARK: - Quick Shift sheet (QuickShiftSheet)

    enum Shift {
        static let sheet            = "shift.sheet"
        static let amountStepper    = "shift.amount_stepper"
        static let applyShiftButton = "shift.apply_button"
        static let cancelButton     = "shift.cancel_button"
    }

    // MARK: - Vendors (VendorManagerView)

    enum Vendors {
        static let addVendorButton = "vendors.add_vendor_button"
        static let vendorList      = "vendors.vendor_list"
        static let customRoleField = "vendors.custom_role_field"
    }

    // MARK: - Templates (TemplateBrowserView)

    enum Templates {
        static let templateList         = "templates.template_list"
        static let sectionPicker        = "templates.section_picker"
        static let myTemplatesGrid      = "templates.my_templates_grid"
        static let starterTemplatesGrid = "templates.starter_templates_grid"
        static let communityTeaser      = "templates.community_teaser"
        static let saveTemplateButton   = "templates.save_template_button"
        static let saveTemplateNameField = "templates.save_template_name_field"
        static let editorSaveButton     = "templates.editor_save_button"
        static let editorNameField      = "templates.editor_name_field"
    }

    // MARK: - Vendor Teams (VendorTeamsView / ApplyVendorTeamSheet)

    enum VendorTeams {
        static let teamList         = "vendor_teams.team_list"
        static let addTeamButton    = "vendor_teams.add_team_button"
        static let teamNameField    = "vendor_teams.team_name_field"
        static let editorSaveButton = "vendor_teams.editor_save_button"
        static let applyTeamButton  = "vendor_teams.apply_team_button"
        static let memberCustomRoleField = "vendor_teams.member_custom_role_field"
    }

    // MARK: - Launch Promo (LaunchPromoView)

    enum LaunchPromo {
        static let closeButton   = "launch_promo.close_button"
        static let upgradeButton = "launch_promo.upgrade_button"
    }

    // MARK: - Marketplace (MarketplaceTeaserView)

    enum Marketplace {
        static let heroTitle             = "marketplace.hero_title"
        static let previewCardList       = "marketplace.preview_card_list"
        static let joinWaitlistButton    = "marketplace.join_waitlist_button"
        static let joinedBadge           = "marketplace.joined_badge"
        static let updateInterestsButton = "marketplace.update_interests_button"
        // Directory (MarketplaceHomeView / VendorSearchResultsView / VendorPublicProfileView)
        static let searchField        = "marketplace.search_field"
        static let categoryChips      = "marketplace.category_chips"
        static let becomeVendorButton = "marketplace.become_vendor_button"
        static let requestsInbox      = "marketplace.requests_inbox"
        static let featuredList       = "marketplace.featured_list"
        static let vendorCard         = "marketplace.vendor_card"
        static let searchResultsList  = "marketplace.search_results_list"
        static let profileHeader      = "marketplace.profile_header"
        static let requestButton      = "marketplace.request_button"
        // Reviews (E17): composer + profile reviews section.
        static let reviewStarPicker   = "marketplace.review_star_picker"
        static let reviewBodyField    = "marketplace.review_body_field"
        static let reviewSubmitButton = "marketplace.review_submit_button"
        static let reviewsList        = "marketplace.reviews_list"
        static let reviewVendorsList  = "marketplace.review_vendors_list"
        // Availability (E18): calendar editor + search date filter.
        static let manageAvailabilityButton = "marketplace.manage_availability_button"
        static let availabilityGrid         = "marketplace.availability_grid"
        static let searchDateChip           = "marketplace.search_date_chip"
    }

    // MARK: - Marketplace Waitlist (WaitlistSignupSheet)

    enum Waitlist {
        static let rolePicker          = "waitlist.role_picker"
        static let categoryPicker      = "waitlist.category_picker"
        static let customCategoryField = "waitlist.custom_category_field"
        static let regionField         = "waitlist.region_field"
        static let submitButton   = "waitlist.submit_button"
        static let cancelButton   = "waitlist.cancel_button"
        static let confirmedState = "waitlist.confirmed_state"
    }

    // MARK: - Marketplace UGC safety (VendorSafetyMenu / ReportReasonSheet)

    enum Safety {
        static let menu               = "safety.menu"
        static let reportButton       = "safety.report_button"
        static let blockButton        = "safety.block_button"
        static let reportSheet        = "safety.report_sheet"
        static let reportCancelButton = "safety.report_cancel_button"
    }

    // MARK: - Post-Event Report (PostEventReportPreviewView)

    enum Report {
        static let exportButton = "report.export_button"
    }

    // MARK: - Forced onboarding (ProfileSetupView)

    enum Onboarding {
        static let root              = "onboarding.root"
        static let plannerCard       = "onboarding.planner_card"
        static let vendorCard        = "onboarding.vendor_card"
        static let plannerNameField  = "onboarding.planner_name_field"
        static let vendorNameField   = "onboarding.vendor_name_field"
        static let submitButton      = "onboarding.submit_button"
    }
}
