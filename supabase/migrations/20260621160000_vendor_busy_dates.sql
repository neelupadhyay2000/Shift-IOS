-- Marketplace Availability (E18) — Story 1: vendor_busy_dates + get_my_calendar
--
-- Vendors mark days they're unavailable. Two sources of "busy":
--   1. MANUAL — rows in this table, owner-only and PRIVATE (never directly
--      readable by other users; only ever surfaced through definer functions).
--   2. BOOKED — derived, NOT materialized: a claimed event_vendors row on an
--      event whose date falls on that day. Computed inside SECURITY DEFINER
--      functions so the booking (planner-owned event) never leaks via RLS.
--
-- Online-only (marketplace Services), like vendor_profiles: not in the SwiftData
-- sync stack or realtime publication. Toggling a day off is a soft-delete
-- (deleted_at) so the unique slot is preserved; toggling back on resurrects the
-- row via upsert (on_conflict (profile_id, busy_date) → deleted_at = null).

create table public.vendor_busy_dates (
    id          uuid primary key default gen_random_uuid(),
    profile_id  uuid not null references public.vendor_profiles(profile_id) on delete cascade,
    busy_date   date not null,
    note        text check (char_length(note) <= 280),

    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now(),
    deleted_at  timestamptz,

    -- One row per (vendor, day). Spans soft-deleted rows: re-marking a day is an
    -- upsert that clears deleted_at rather than a second insert.
    unique (profile_id, busy_date)
);

comment on table public.vendor_busy_dates
    is 'Manual vendor unavailability (E18). Owner-only + PRIVATE — never directly '
       'readable by other users; availability is exposed only via SECURITY DEFINER '
       'functions (get_my_calendar, search_vendors p_on_date) that union these with '
       'derived bookings. Online-only; not in the sync stack/realtime publication.';

-- Calendar-range scans for one vendor.
create index vendor_busy_dates_profile_date_idx
    on public.vendor_busy_dates (profile_id, busy_date)
    where deleted_at is null;

-- set_updated_at trigger (shared, SHIFT-556).
create trigger set_updated_at
    before update on public.vendor_busy_dates
    for each row execute function public.set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- RLS: owner-only. Manual unavailability is private to the vendor.
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.vendor_busy_dates enable row level security;

create policy "vendor_busy_dates_self_all" on public.vendor_busy_dates
    for all
    to authenticated
    using (profile_id = auth.uid())
    with check (profile_id = auth.uid());

revoke all on public.vendor_busy_dates from anon;

-- ─────────────────────────────────────────────────────────────────────────────
-- get_my_calendar(p_from, p_to) — the calling vendor's own calendar editor data.
--
-- Unions manual busy dates with derived bookings (claimed event_vendors joined to
-- events whose date is in range). SECURITY DEFINER so the booked side reads
-- planner-owned events past RLS; auth.uid() still resolves to the caller, so it
-- only ever returns the caller's own data. A day can appear twice (manual AND
-- booked) — the client treats any booked day as locked.
--
-- NOTE: events.date is a timestamptz; it's cast to date in the server timezone.
-- Good enough for v1 day-granularity availability.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_my_calendar(p_from date, p_to date)
returns table (
    busy_date   date,
    kind        text,
    event_title text
)
language sql
stable
security definer
set search_path = ''
as $$
    select b.busy_date, 'manual'::text as kind, null::text as event_title
      from public.vendor_busy_dates b
     where b.profile_id = auth.uid()
       and b.deleted_at is null
       and b.busy_date between p_from and p_to
    union all
    select (e.date)::date as busy_date, 'booked'::text as kind, e.title as event_title
      from public.event_vendors ev
      join public.events e on e.id = ev.event_id
     where ev.profile_id = auth.uid()
       and ev.accepted_at is not null
       and ev.deleted_at is null
       and e.deleted_at is null
       and (e.date)::date between p_from and p_to
    order by busy_date;
$$;

comment on function public.get_my_calendar(date, date)
    is 'Calling vendor''s own calendar (E18): manual busy dates UNION derived '
       'bookings (claimed events in range), with kind (manual|booked) + event '
       'title for booked days. SECURITY DEFINER; auth.uid()-scoped to the caller.';

revoke all on function public.get_my_calendar(date, date) from public, anon;
grant execute on function public.get_my_calendar(date, date) to authenticated;
