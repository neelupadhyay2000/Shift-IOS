import Foundation

/// Centralised, namespaced accessibility identifier strings — test-target copy.
///
/// This file is intentionally identical to `shiftTimeline/Design/AccessibilityID.swift`
/// in the app target. Because the UITest runner is a separate process it cannot
/// import the app module, so the constants are duplicated here. If you add or
/// rename an identifier, update **both** files.
///
/// Naming convention: `<screen>.<element_role>` — lowercase, dot-separated.
enum AccessibilityID {

    // MARK: - Tab bar

    enum Tab {
        static let events    = "tab.events"
        static let templates = "tab.templates"
        static let settings  = "tab.settings"
    }

    // MARK: - Event Roster (EventRosterView)

    enum Roster {
        static let addEventButton    = "roster.add_event_button"
        static let statusFilter      = "roster.status_filter"
        static let eventList         = "roster.event_list"
        static let createEventButton = "roster.create_event_button"
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
    }

    // MARK: - Templates (TemplateBrowserView)

    enum Templates {
        static let templateList = "templates.template_list"
    }

    // MARK: - Post-Event Report (PostEventReportPreviewView)

    enum Report {
        static let exportButton = "report.export_button"
    }
}
