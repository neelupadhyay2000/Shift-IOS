-- Marketplace Directory (vendor discovery) — Story 1: vendor_profiles
--
-- 1:1 extension of profiles holding the marketplace-only vendor fields: category,
-- service area + geo, skills, listing toggle, and rollup stats. Display identity
-- (business_name, bio, avatar_url) stays canonical on profiles (reserved columns,
-- see 20260604170829_profiles.sql) — the public directory joins public_profiles
-- for those, so this table never duplicates them.
--
-- Online-only by design: written directly by the app (marketplace Services), the
-- same posture as marketplace_waitlist. It is NOT part of the SwiftData/Outbox
-- sync stack and is intentionally excluded from the realtime publication.
--
-- RLS posture (new for the marketplace): a self-only full-access policy plus a
-- public-read policy scoped to listed, non-deleted rows — for AUTHENTICATED users
-- only. anon never gets access (no anon policy; grants explicitly revoked below).

-- pg_trgm backs the fuzzy search_name index used by the search_vendors RPC (later
-- story). Idempotent: harmless if another migration already enabled it.
create extension if not exists pg_trgm;

create table public.vendor_profiles (
    profile_id              uuid primary key references public.profiles(id) on delete cascade,

    -- VendorRole rawValue; 'custom' carries a free-text type (no CHECK, mirroring
    -- event_vendors.role). Default keeps a freshly-created row valid before edit.
    category                text not null default 'custom',

    -- Free-text service area label + coordinates for the haversine radius search
    -- (no PostGIS in v1). service_radius_km is the vendor's travel willingness.
    service_area            text,
    latitude                double precision,
    longitude               double precision,
    service_radius_km       double precision default 80,

    skills                  text[] not null default '{}',

    -- Lowercase denormalisation of profiles.business_name, maintained by the
    -- profile editor write path so the trigram index has a stable search target.
    search_name             text,

    -- Off by default: a vendor is invisible to the directory until they opt in.
    is_listed               boolean not null default false,

    -- Rollup stats. events_completed_count + ratings are populated by E13 triggers;
    -- rating_avg stays null until the first rating lands.
    events_completed_count  int not null default 0,
    rating_avg              numeric(3,2),
    rating_count            int not null default 0,

    -- Sync metadata (repo convention; updated_at bumped by the trigger below).
    created_at              timestamptz not null default now(),
    updated_at              timestamptz not null default now(),
    deleted_at              timestamptz
);

comment on table public.vendor_profiles
    is 'Marketplace vendor directory profile (1:1 with profiles via profile_id). '
       'Online-only, not in the SwiftData sync stack or realtime publication. '
       'Identity display fields stay on profiles/public_profiles; this table holds '
       'category, geo/service area, skills, the is_listed opt-in, and rollup stats. '
       'RLS: self-all + authenticated public_select on listed rows; never anon.';

-- ─────────────────────────────────────────────────────────────────────────────
-- Indexes
-- ─────────────────────────────────────────────────────────────────────────────
-- Trigram fuzzy match on the denormalised name (search_vendors RPC).
create index vendor_profiles_search_name_trgm
    on public.vendor_profiles using gin (search_name gin_trgm_ops);

-- Skills overlap (&&) / containment for the skills filter.
create index vendor_profiles_skills_gin
    on public.vendor_profiles using gin (skills);

-- Category browse over the listed directory only (partial index stays small).
create index vendor_profiles_category_listed
    on public.vendor_profiles (category)
    where is_listed;

-- ─────────────────────────────────────────────────────────────────────────────
-- updated_at bump — shared trigger function from SHIFT-556
-- ─────────────────────────────────────────────────────────────────────────────
create trigger set_updated_at
    before update on public.vendor_profiles
    for each row execute function public.set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- RLS
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.vendor_profiles enable row level security;

-- Self: full CRUD on own row only (mirrors profiles_self_all).
create policy "vendor_profiles_self_all" on public.vendor_profiles
    for all
    to authenticated
    using (profile_id = auth.uid())
    with check (profile_id = auth.uid());

-- Directory: any authenticated user may read listed, non-deleted profiles.
create policy "vendor_profiles_public_select" on public.vendor_profiles
    for select
    to authenticated
    using (is_listed and deleted_at is null);

-- Never expose to anon. RLS alone already blocks anon (no anon policy), but the
-- Data API auto-grants table privileges to anon on new public tables, so revoke
-- them explicitly to keep the marketplace authenticated-only.
revoke all on public.vendor_profiles from anon;
