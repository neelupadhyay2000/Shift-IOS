-- Marketplace Directory (vendor discovery) — Story 2: portfolio_items + the moat
--
-- A vendor's portfolio is a list of items, each either:
--   'photo'        → an uploaded image (storage_path into the vendor-portfolio bucket)
--   'shift_event'  → a SERVER-VERIFIED reference to an event the vendor actually
--                    worked: they were an accepted event_vendor on a COMPLETED
--                    event. This verification is the marketplace moat — portfolios
--                    cannot be faked — and is enforced by a BEFORE trigger, not the
--                    client.
--
-- Online-only, like vendor_profiles: not in the SwiftData/Outbox sync stack or the
-- realtime publication.

create table public.portfolio_items (
    id              uuid primary key default gen_random_uuid(),
    profile_id      uuid not null references public.vendor_profiles(profile_id) on delete cascade,

    kind            text not null check (kind in ('photo', 'shift_event')),

    -- 'photo' payload: object path in the vendor-portfolio storage bucket.
    storage_path    text,
    -- 'shift_event' payload: the worked event. set null (not cascade) so deleting
    -- an event leaves the row to be cleaned up rather than silently vanishing a
    -- portfolio entry mid-read; the verify trigger + RPC ignore null/uncompleted.
    event_id        uuid references public.events(id) on delete set null,

    caption         text,
    sort_order      int not null default 0,

    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now(),
    deleted_at      timestamptz,

    -- Kind/payload coherence (the verify trigger enforces the moat on top of this).
    constraint portfolio_items_kind_payload check (
        (kind = 'photo' and storage_path is not null)
        or (kind = 'shift_event' and event_id is not null)
    )
);

comment on table public.portfolio_items
    is 'Vendor portfolio entries (photo | shift_event). shift_event items are '
       'server-verified by the portfolio_items_verify trigger (accepted vendor on '
       'a completed event) — the anti-fake moat. Online-only; not in the sync '
       'stack or realtime publication.';

-- Owner listing / RPC join; partial keeps it lean over live rows.
create index portfolio_items_profile_idx
    on public.portfolio_items (profile_id, sort_order)
    where deleted_at is null;

-- FK lookups (Postgres does not auto-index FKs); used by the on-delete set-null.
create index portfolio_items_event_idx
    on public.portfolio_items (event_id)
    where event_id is not null;

-- ─────────────────────────────────────────────────────────────────────────────
-- Verification helper (SECURITY DEFINER) — the moat
--
-- True when p_profile_id was an ACCEPTED vendor on a COMPLETED, non-deleted event.
-- SECURITY DEFINER so it reads events/event_vendors regardless of the caller's own
-- RLS (a vendor cannot necessarily SELECT the planner's event row), avoiding RLS
-- recursion from inside the trigger. search_path = '' + schema-qualified refs.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.is_completed_event_vendor(p_event_id uuid, p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.event_vendors v
        join public.events e on e.id = v.event_id
        where v.event_id = p_event_id
          and v.profile_id = p_profile_id
          and v.accepted_at is not null
          and v.deleted_at is null
          and e.status = 'completed'
          and e.deleted_at is null
    )
$$;

comment on function public.is_completed_event_vendor(uuid, uuid)
    is 'True if p_profile_id was an accepted vendor on a completed, non-deleted '
       'event. SECURITY DEFINER to bypass caller RLS; backs the portfolio_items '
       'shift_event verification trigger.';

-- ─────────────────────────────────────────────────────────────────────────────
-- BEFORE INSERT/UPDATE trigger — reject unverifiable shift_event items
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.portfolio_items_verify()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    -- Photo items carry no event claim; nothing to verify here (the CHECK
    -- constraint already guarantees storage_path is present).
    if new.kind = 'shift_event' then
        if not public.is_completed_event_vendor(new.event_id, new.profile_id) then
            raise exception
                'portfolio_items: profile % is not an accepted vendor on completed event %',
                new.profile_id, new.event_id
                using errcode = 'check_violation';
        end if;
    end if;
    return new;
end;
$$;

comment on function public.portfolio_items_verify()
    is 'BEFORE INSERT/UPDATE on portfolio_items: blocks shift_event items unless '
       'is_completed_event_vendor() confirms the vendor worked the completed event. '
       'The marketplace anti-fake moat.';

create trigger portfolio_items_verify
    before insert or update on public.portfolio_items
    for each row execute function public.portfolio_items_verify();

-- updated_at bump — shared trigger function from SHIFT-556.
create trigger set_updated_at
    before update on public.portfolio_items
    for each row execute function public.set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- RLS
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.portfolio_items enable row level security;

-- Owner: full CRUD on own items.
create policy "portfolio_items_owner_all" on public.portfolio_items
    for all
    to authenticated
    using (profile_id = auth.uid())
    with check (profile_id = auth.uid());

-- Directory: any authenticated user may read a vendor's items, but only while the
-- parent vendor_profile is listed (and neither is soft-deleted). The EXISTS runs
-- under the caller's RLS — vendor_profiles_public_select already exposes listed
-- rows — so unlisted vendors' portfolios stay invisible.
create policy "portfolio_items_public_select" on public.portfolio_items
    for select
    to authenticated
    using (
        deleted_at is null
        and exists (
            select 1
            from public.vendor_profiles vp
            where vp.profile_id = portfolio_items.profile_id
              and vp.is_listed
              and vp.deleted_at is null
        )
    );

-- Authenticated-only marketplace: never anon.
revoke all on public.portfolio_items from anon;

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC get_portfolio_event_summaries — hydrate shift_event titles/dates
--
-- The directory shows event title + date for a vendor's verified shift_event
-- items, but planners must NOT gain read access to other planners' events. Rather
-- than widen events RLS, this SECURITY DEFINER RPC returns ONLY the summary fields
-- for that vendor's verified, listed-or-owned portfolio events.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_portfolio_event_summaries(p_profile_id uuid)
returns table (event_id uuid, title text, event_date timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
    select e.id, e.title, e.date
    from public.portfolio_items pi
    join public.events e on e.id = pi.event_id
    where pi.profile_id = p_profile_id
      and pi.kind = 'shift_event'
      and pi.deleted_at is null
      and e.deleted_at is null
      and e.status = 'completed'
      -- Mirror portfolio_items_public_select visibility: owner always, others only
      -- when the vendor profile is listed. (RLS is bypassed here, so gate explicitly.)
      and (
        p_profile_id = auth.uid()
        or exists (
            select 1
            from public.vendor_profiles vp
            where vp.profile_id = p_profile_id
              and vp.is_listed
              and vp.deleted_at is null
        )
      )
    order by pi.sort_order;
$$;

comment on function public.get_portfolio_event_summaries(uuid)
    is 'Returns (event_id, title, date) for a vendor''s verified shift_event '
       'portfolio items. SECURITY DEFINER so the directory can show event '
       'summaries without widening events RLS; visibility mirrors '
       'portfolio_items_public_select (owner, or listed vendor).';

revoke all on function public.get_portfolio_event_summaries(uuid) from public;
revoke all on function public.get_portfolio_event_summaries(uuid) from anon;
grant execute on function public.get_portfolio_event_summaries(uuid) to authenticated;
