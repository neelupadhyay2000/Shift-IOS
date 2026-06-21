-- Marketplace pro polish (E22): saved vendors + search sort
--
-- 1. saved_vendors: a planner's shortlist of favourited vendors (owner-only).
-- 2. get_saved_vendors(): the caller's saved + listed vendors as directory cards.
-- 3. search_vendors gains p_sort ('rating' | 'booked' | 'nearest') so the planner
--    Filters/Sort sheet can reorder results server-side.

-- ─────────────────────────────────────────────────────────────────────────────
-- saved_vendors
-- ─────────────────────────────────────────────────────────────────────────────
create table public.saved_vendors (
    planner_id        uuid not null references public.profiles(id) on delete cascade,
    vendor_profile_id uuid not null references public.vendor_profiles(profile_id) on delete cascade,
    created_at        timestamptz not null default now(),
    primary key (planner_id, vendor_profile_id)
);

comment on table public.saved_vendors
    is 'A planner''s favourited vendors (E22). Owner-only RLS; surfaced as cards '
       'via get_saved_vendors. Online-only, not in the sync stack.';

create index saved_vendors_planner_idx on public.saved_vendors (planner_id, created_at desc);

alter table public.saved_vendors enable row level security;

create policy "saved_vendors_self_all" on public.saved_vendors
    for all
    to authenticated
    using (planner_id = auth.uid())
    with check (planner_id = auth.uid());

revoke all on public.saved_vendors from anon;

-- ─────────────────────────────────────────────────────────────────────────────
-- get_saved_vendors() — caller's saved + listed vendors as vendor_search_result.
-- SECURITY DEFINER (reads vendor_profiles/public_profiles past RLS); newest-saved
-- first; drops blocked vendors and any whose listing went away.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_saved_vendors()
returns setof public.vendor_search_result
language sql
stable
security definer
set search_path = ''
as $$
    select
        vp.profile_id, pp.display_name, pp.business_name, pp.bio, pp.avatar_url,
        vp.category, vp.skills, vp.service_area, vp.latitude, vp.longitude,
        vp.service_radius_km, vp.events_completed_count, vp.rating_avg, vp.rating_count,
        null::double precision as distance_km
    from public.saved_vendors sv
    join public.vendor_profiles vp on vp.profile_id = sv.vendor_profile_id
    join public.public_profiles pp on pp.id = vp.profile_id
    where sv.planner_id = auth.uid()
      and vp.is_listed
      and vp.deleted_at is null
      and not exists (
          select 1 from public.user_blocks b
          where (b.blocker_id = auth.uid() and b.blocked_id = vp.profile_id)
             or (b.blocker_id = vp.profile_id and b.blocked_id = auth.uid())
      )
    order by sv.created_at desc;
$$;

comment on function public.get_saved_vendors()
    is 'The caller''s saved + listed vendors as directory cards (E22), newest first.';

revoke all on function public.get_saved_vendors() from public, anon;
grant execute on function public.get_saved_vendors() to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- search_vendors + p_sort. Drop the 8-arg signature first (a 9th defaulted param
-- would make the old call ambiguous — same reason as the p_on_date migration).
-- ─────────────────────────────────────────────────────────────────────────────
drop function if exists public.search_vendors(
    text, text, double precision, double precision, double precision, int, int, date
);

create or replace function public.search_vendors(
    p_query      text             default null,
    p_category   text             default null,
    p_lat        double precision default null,
    p_lng        double precision default null,
    p_radius_km  double precision default null,
    p_limit      int              default 20,
    p_offset     int              default 0,
    p_on_date    date             default null,
    p_sort       text             default null   -- 'rating' | 'booked' | 'nearest'
)
returns setof public.vendor_search_result
language sql
stable
security definer
set search_path = ''
as $$
    with matched as (
        select
            vp.profile_id, pp.display_name, pp.business_name, pp.bio, pp.avatar_url,
            vp.category, vp.skills, vp.service_area, vp.latitude, vp.longitude,
            vp.service_radius_km, vp.events_completed_count, vp.rating_avg, vp.rating_count,
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
          and (
              nullif(btrim(p_query), '') is null
              or vp.search_name ilike '%' || lower(btrim(p_query)) || '%'
              or vp.skills && array[lower(btrim(p_query))]
          )
          and (
              nullif(btrim(p_category), '') is null
              or vp.category = p_category
          )
          and not exists (
              select 1
              from public.user_blocks b
              where (b.blocker_id = auth.uid() and b.blocked_id = vp.profile_id)
                 or (b.blocker_id = vp.profile_id and b.blocked_id = auth.uid())
          )
          and (
              p_on_date is null
              or not exists (
                  select 1 from public.vendor_busy_dates bd
                  where bd.profile_id = vp.profile_id and bd.deleted_at is null and bd.busy_date = p_on_date
              )
          )
          and (
              p_on_date is null
              or not exists (
                  select 1
                  from public.event_vendors ev
                  join public.events e on e.id = ev.event_id
                  where ev.profile_id = vp.profile_id
                    and ev.accepted_at is not null
                    and ev.deleted_at is null
                    and e.deleted_at is null
                    and (e.date)::date = p_on_date
              )
          )
    )
    select
        profile_id, display_name, business_name, bio, avatar_url,
        category, skills, service_area, latitude, longitude, service_radius_km,
        events_completed_count, rating_avg, rating_count, distance_km
    from matched
    where p_lat is null or p_lng is null or p_radius_km is null
       or (distance_km is not null and distance_km <= p_radius_km)
    order by
        -- 'nearest' only meaningful when a point was supplied; nulls sort last.
        case when p_sort = 'nearest' then distance_km end asc nulls last,
        case when p_sort = 'booked'  then events_completed_count end desc nulls last,
        -- default + 'rating': rating first, then most-booked (the E10 ordering).
        rating_avg desc nulls last,
        events_completed_count desc,
        profile_id
    limit  least(greatest(coalesce(p_limit, 20), 1), 50)
    offset greatest(coalesce(p_offset, 0), 0);
$$;

comment on function public.search_vendors(text, text, double precision, double precision, double precision, int, int, date, text)
    is 'Vendor directory search (E10/E18/E22). Filters: name/skills, category, '
       'haversine radius, p_on_date availability. p_sort: rating|booked|nearest. '
       'SECURITY DEFINER; blocked vendors excluded both directions.';

revoke all on function public.search_vendors(text, text, double precision, double precision, double precision, int, int, date, text) from public, anon;
grant execute on function public.search_vendors(text, text, double precision, double precision, double precision, int, int, date, text) to authenticated;
