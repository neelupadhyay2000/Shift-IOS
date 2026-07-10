## ADDED Requirements

### Requirement: Vendors manage manual unavailability privately
A vendor SHALL be able to mark and unmark individual calendar days as busy. Manual busy days are stored in `vendor_busy_dates` and are PRIVATE — owner-only RLS (`profile_id = auth.uid()`) means no other user can read them directly; they are only ever consulted inside SECURITY DEFINER functions. Marking a day toggles a row keyed by the unique `(profile_id, busy_date)`; unmarking soft-deletes it; re-marking resurrects the same slot via upsert clearing `deleted_at`.

#### Scenario: Toggle a day busy then available
- **WHEN** a vendor taps an available day in `AvailabilityCalendarView`
- **THEN** `AvailabilityService.markBusy(date:note:)` upserts a `vendor_busy_dates` row and the day renders busy
- **WHEN** the vendor taps that busy day again
- **THEN** `AvailabilityService.clearBusy(date:)` soft-deletes the row and the day renders available

#### Scenario: Manual busy dates never leak
- **WHEN** any user other than the owner queries `vendor_busy_dates`
- **THEN** owner-only RLS returns zero rows — manual unavailability is never directly readable

### Requirement: Booked Shift events count as busy automatically
A day on which the vendor has a claimed `event_vendors` row for an event dated that day SHALL be treated as busy without any manual action. Bookings are DERIVED, not materialized: availability is computed by unioning manual busy dates with claimed-event dates inside SECURITY DEFINER functions, so a booking (a planner-owned event) is consulted but never exposed.

#### Scenario: Calendar shows booked days locked
- **WHEN** a vendor opens `AvailabilityCalendarView` for a month containing an event they are claimed on
- **THEN** `get_my_calendar(from,to)` returns that day with `kind = booked` and the event title, and the calendar renders it locked (not togglable), showing the event title on tap

### Requirement: Planners filter vendor search by event date
`search_vendors` SHALL accept an optional `p_on_date`. When provided, a vendor is excluded if they are manually busy that day OR booked on an event dated that day; both checks run definer-side so private busy data and other planners' bookings are consulted but never returned. When `p_on_date` is null, results are unchanged from the directory baseline.

#### Scenario: Manually busy vendor excluded on the filtered date
- **WHEN** a planner runs vendor search with a date on which a vendor has a manual busy row
- **THEN** that vendor does not appear in the results, while vendors free that day do

#### Scenario: Booked vendor excluded on the filtered date
- **WHEN** a planner runs vendor search with a date on which a vendor is claimed on an event dated that day
- **THEN** that vendor does not appear in the results

#### Scenario: Date filter UI defaults from event context
- **WHEN** vendor search is opened with an event-date context (`MarketplaceDestination.searchResults(onDate:)`)
- **THEN** the date filter chip defaults to that date and reads "Available on <Mon D>", and the planner can change or clear it
