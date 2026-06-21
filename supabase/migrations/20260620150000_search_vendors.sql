-- Marketplace Directory (vendor discovery) — Story 4: search_vendors RPC
--
-- Server-side vendor matching so the logic can evolve without an app release.
-- v1 matching (no PostGIS): trigram/ILIKE on the denormalised search_name,
-- skills array overlap, category equality, and a haversine radius on lat/lng.
--
-- Ships with the user_blocks table it depends on (block exclusion is part of the
-- search contract). The UGC-safety story layers content_reports + the report flow
-- on top; the block table itself lives here so search can launch self-contained.
--
-- E14 will extend this RPC with availability filtering (p_on_date) — the body is
-- structured as a single CTE + final select so that becomes a localized NOT EXISTS
-- against the future bookings table, with no signature break beyond the new param.

-- ─────────────────────────────────────────────────────────────────────────────
-- user_blocks — one row per (blocker → blocked) pair
-- ─────────────────────────────────────────────────────────────────────────────
create table public.user_blocks (
    blocker_id  uuid not null references public.profiles(id) on delete cascade,
    blocked_id  uuid not null references public.profiles(id) on delete cascade,
    created_at  timestamptz not null default now(),

    primary key (blocker_id, blocked_id),
    constraint user_blocks_no_self check (blocker_id <> blocked_id)
);

comment on table public.user_blocks
    is 'Directional block list (blocker_id blocks blocked_id). Backs Apple '
       'Guideline 1.2 blocking and is applied bidirectionally by search_vendors. '
       'RLS: a user manages and sees only their own outgoing blocks.';

-- Reverse-direction lookup ("who has blocked me"); the PK covers the forward one.
create index user_blocks_blocked_idx on public.user_blocks (blocked_id);

alter table public.user_blocks enable row level security;

-- A user can create/see/remove only their own outgoing blocks. They cannot see
-- rows where they are the blocked party (that asymmetry is intentional — the
-- bidirectional hide is enforced inside the SECURITY DEFINER search RPC).
create policy "user_blocks_blocker_all" on public.user_blocks
    for all
    to authenticated
    using (blocker_id = auth.uid())
    with check (blocker_id = auth.uid());

revoke all on public.user_blocks from anon;

-- ─────────────────────────────────────────────────────────────────────────────
-- Composite result type
-- ─────────────────────────────────────────────────────────────────────────────
create type public.vendor_search_result as (
    profile_id              uuid,
    -- Display identity (joined from public_profiles — the safe projection).
    display_name            text,
    business_name           text,
    bio                     text,
    avatar_url              text,
    -- Marketplace fields.
    category                text,
    skills                  text[],
    service_area            text,
    latitude                double precision,
    longitude               double precision,
    service_radius_km       double precision,
    -- Stats (populated by E13 triggers).
    events_completed_count  int,
    rating_avg              numeric(3,2),
    rating_count            int,
    -- Computed haversine distance from the caller's point, null when no point
    -- was supplied or the vendor has no coordinates.
    distance_km             double precision
);

-- ─────────────────────────────────────────────────────────────────────────────
-- search_vendors RPC
--
-- SECURITY DEFINER so it can read vendor_profiles/user_blocks regardless of the
-- caller's RLS and apply the block exclusion in BOTH directions (the caller
-- cannot SELECT rows where they are the blocked party). is_listed + non-deleted
-- gating is applied explicitly. search_path = '' with fully-qualified names; the
-- trigram GIN index accelerates the ILIKE, and the GIN skills index the overlap,
-- so no pg_trgm operator (which lives in public) is needed under the pinned path.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.search_vendors(
    p_query      text             default null,
    p_category   text             default null,
    p_lat        double precision default null,
    p_lng        double precision default null,
    p_radius_km  double precision default null,
    p_limit      int              default 20,
    p_offset     int              default 0
)
returns setof public.vendor_search_result
language sql
stable
security definer
set search_path = ''
as $$
    with matched as (
        select
            vp.profile_id,
            pp.display_name,
            pp.business_name,
            pp.bio,
            pp.avatar_url,
            vp.category,
            vp.skills,
            vp.service_area,
            vp.latitude,
            vp.longitude,
            vp.service_radius_km,
            vp.events_completed_count,
            vp.rating_avg,
            vp.rating_count,
            -- Haversine (km, R=6371) when both the caller's point and the vendor's
            -- coordinates are present; null otherwise.
            case
                when p_lat is not null and p_lng is not null
                     and vp.latitude is not null and vp.longitude is not null
                then 2 * 6371 * asin(sqrt(
                        sin(radians(vp.latitude - p_lat) / 2) ^ 2
                        + cos(radians(p_lat)) * cos(radians(vp.latitude))
                          * sin(radians(vp.longitude - p_lng) / 2) ^ 2
                     ))
            end as distance_km
        from public.vendor_profiles vp
        join public.public_profiles pp on pp.id = vp.profile_id
        where vp.is_listed
          and vp.deleted_at is null
          -- Text query: substring/trigram on the name, or a skills-tag overlap.
          -- (skills are stored lowercase by the profile editor write path.)
          and (
              nullif(btrim(p_query), '') is null
              or vp.search_name ilike '%' || lower(btrim(p_query)) || '%'
              or vp.skills && array[lower(btrim(p_query))]
          )
          -- Category equality.
          and (
              nullif(btrim(p_category), '') is null
              or vp.category = p_category
          )
          -- Block exclusion, both directions.
          and not exists (
              select 1
              from public.user_blocks b
              where (b.blocker_id = auth.uid() and b.blocked_id = vp.profile_id)
                 or (b.blocker_id = vp.profile_id and b.blocked_id = auth.uid())
          )
          -- E14: availability filter (p_on_date) plugs in here.
    )
    select
        profile_id, display_name, business_name, bio, avatar_url,
        category, skills, service_area, latitude, longitude, service_radius_km,
        events_completed_count, rating_avg, rating_count, distance_km
    from matched
    -- Radius applies only when the caller supplies a point and a radius; a vendor
    -- with no coordinates is excluded from a radius search (distance_km is null).
    where p_lat is null
       or p_lng is null
       or p_radius_km is null
       or (distance_km is not null and distance_km <= p_radius_km)
    order by
        rating_avg desc nulls last,
        events_completed_count desc,
        profile_id                       -- stable tiebreak for offset paging
    limit  least(greatest(coalesce(p_limit, 20), 1), 50)
    offset greatest(coalesce(p_offset, 0), 0);
$$;

comment on function public.search_vendors(text, text, double precision, double precision, double precision, int, int)
    is 'Vendor directory search over listed, non-deleted vendor_profiles: ILIKE/'
       'trigram name match, skills overlap, category equality, haversine radius '
       '(no PostGIS). Excludes blocked vendors both directions via user_blocks. '
       'SECURITY DEFINER; ordered by rating_avg desc nulls last, '
       'events_completed_count desc. E14 adds p_on_date availability.';

-- Authenticated-only; never anon / public.
revoke all on function public.search_vendors(text, text, double precision, double precision, double precision, int, int) from public;
revoke all on function public.search_vendors(text, text, double precision, double precision, double precision, int, int) from anon;
grant execute on function public.search_vendors(text, text, double precision, double precision, double precision, int, int) to authenticated;
