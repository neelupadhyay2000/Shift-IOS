-- Marketplace Requests (E11) — Story 1: service_requests
--
-- A planner sends a service request to a marketplace vendor, tied to an event
-- (optionally specific blocks + a note). The vendor accepts/declines via the
-- SECURITY DEFINER respond_to_service_request RPC (next story) — which, on accept,
-- claims an event_vendors row so can_access_event() becomes true and ALL existing
-- collaboration (read-only timeline, shift acks, go-live pushes) activates.
--
-- The request snapshots the event title/date and the requested blocks so the
-- vendor can render it WITHOUT event access before accepting (pre-accept they have
-- no RLS path to the event).

create table public.service_requests (
    id                uuid primary key default gen_random_uuid(),
    event_id          uuid not null references public.events(id) on delete cascade,
    -- Denormalized event owner (the requesting planner).
    planner_id        uuid not null references public.profiles(id) on delete cascade,
    -- The targeted vendor's profile id (= their auth.uid()). FK to profiles (not
    -- vendor_profiles) so a vendor un-listing doesn't cascade-delete history.
    vendor_profile_id uuid not null references public.profiles(id) on delete cascade,

    status            text not null default 'pending'
                          check (status in ('pending', 'accepted', 'declined', 'cancelled')),
    note              text,

    -- Snapshot of the requested blocks: [{block_id, title, start, end}].
    requested_blocks  jsonb not null default '[]',
    -- Event snapshots so the vendor renders the request with no event access.
    event_title       text not null default '',
    event_date        timestamptz,

    -- Set by the response RPC.
    response_message  text,
    responded_at      timestamptz,
    event_vendor_id   uuid references public.event_vendors(id) on delete set null,

    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz
);

comment on table public.service_requests
    is 'Planner→vendor service requests tied to an event. Vendor responds only via '
       'respond_to_service_request RPC (accept claims an event_vendors row, '
       'activating existing collaboration). Snapshots event title/date + requested '
       'blocks so the vendor renders the request pre-accept without event access. '
       'In the realtime publication so the planner sees responses live.';

-- One open (pending) request per (event, vendor); re-requestable after a
-- decline/cancel since those rows fall out of the partial index.
create unique index uq_service_requests_active
    on public.service_requests (event_id, vendor_profile_id)
    where status = 'pending' and deleted_at is null;

-- Vendor inbox lookups; planner response feed.
create index service_requests_vendor_idx
    on public.service_requests (vendor_profile_id, status)
    where deleted_at is null;

-- set_updated_at trigger (shared, SHIFT-556).
create trigger set_updated_at
    before update on public.service_requests
    for each row execute function public.set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- RLS
--
-- Planner: read own; insert only for events they own (status must start pending);
--   update ONLY to cancel a still-pending request (column-immutability WITH CHECK
--   pattern from 20260604174209_rls_policies_event_vendors.sql — only `status`
--   may change, and only to 'cancelled').
-- Vendor: read requests addressed to them. They never UPDATE directly — accept/
--   decline goes through the SECURITY DEFINER RPC.
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.service_requests enable row level security;

create policy "sr_planner_select" on public.service_requests
    for select
    to authenticated
    using (planner_id = auth.uid());

create policy "sr_planner_insert" on public.service_requests
    for insert
    to authenticated
    with check (
        planner_id = auth.uid()
        and status = 'pending'
        and exists (
            select 1 from public.events e
            where e.id = service_requests.event_id
              and e.owner_id = auth.uid()
              and e.deleted_at is null
        )
    );

create policy "sr_planner_update_cancel" on public.service_requests
    for update
    to authenticated
    using (planner_id = auth.uid() and status = 'pending')
    with check (
        planner_id = auth.uid()
        and status = 'cancelled'
        -- Every other column must be identical to the stored row: the planner may
        -- only flip status pending → cancelled (updated_at is trigger-managed).
        and (
            select
                stored.event_id          = service_requests.event_id
                and stored.planner_id        = service_requests.planner_id
                and stored.vendor_profile_id = service_requests.vendor_profile_id
                and stored.note              is not distinct from service_requests.note
                and stored.requested_blocks  = service_requests.requested_blocks
                and stored.event_title       = service_requests.event_title
                and stored.event_date        is not distinct from service_requests.event_date
                and stored.response_message  is not distinct from service_requests.response_message
                and stored.responded_at      is not distinct from service_requests.responded_at
                and stored.event_vendor_id   is not distinct from service_requests.event_vendor_id
                and stored.created_at         = service_requests.created_at
                and stored.deleted_at        is not distinct from service_requests.deleted_at
            from public.service_requests stored
            where stored.id = service_requests.id
        )
    );

create policy "sr_vendor_select" on public.service_requests
    for select
    to authenticated
    using (vendor_profile_id = auth.uid());

-- Authenticated-only; never anon.
revoke all on public.service_requests from anon;

-- ─────────────────────────────────────────────────────────────────────────────
-- Realtime: planner watches for the vendor's response in place.
-- (RLS still applies — only rows the connected user can SELECT are broadcast.)
-- ─────────────────────────────────────────────────────────────────────────────
alter publication supabase_realtime add table public.service_requests;
