-- SHIFT-677: marketplace_waitlist — demand capture for the marketplace tease.
--
-- One row per profile recording marketplace interest ahead of the vendor
-- marketplace launch (E10–E14): which side of the marketplace they're on
-- (vendor / planner / both), their vendor category, and their region.
-- Written directly by the app (WaitlistService, online-only) — this table is
-- NOT part of SwiftData sync, so it is intentionally excluded from the
-- realtime publication (supabase_realtime).

create table public.marketplace_waitlist (
    id              uuid primary key default gen_random_uuid(),
    profile_id      uuid not null unique references public.profiles(id) on delete cascade,
    interest_role   text not null check (interest_role in ('vendor', 'planner', 'both')),
    category        text,                       -- VendorRole rawValue; only meaningful for vendor signups
    region          text not null default '',

    -- Sync metadata (repo convention; updated_at bumped by trigger below)
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now(),
    deleted_at      timestamptz
);

comment on table public.marketplace_waitlist
    is 'Marketplace launch waitlist (SHIFT-677): one row per profile capturing '
       'interest_role (vendor/planner/both), vendor category, and region. '
       'Self-only RLS; app writes via WaitlistService (online-only, no sync); '
       'not in the realtime publication.';

-- ─────────────────────────────────────────────────────────────────────────────
-- updated_at bump — shared trigger function from SHIFT-556
-- ─────────────────────────────────────────────────────────────────────────────
create trigger set_updated_at
    before update on public.marketplace_waitlist
    for each row execute function public.set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- RLS: self-only full access (mirrors profiles_self_all)
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.marketplace_waitlist enable row level security;

create policy "marketplace_waitlist_self_all" on public.marketplace_waitlist
    for all
    to authenticated
    using (profile_id = auth.uid())
    with check (profile_id = auth.uid());
