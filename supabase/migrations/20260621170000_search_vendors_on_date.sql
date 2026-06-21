-- Marketplace Availability (E18) — Story 2: search_vendors availability filter
--
-- Adds p_on_date to search_vendors. When provided, a vendor is excluded if they
-- are EITHER manually busy that day (vendor_busy_dates) OR booked — a claimed
-- event_vendors row on an event dated that day. Both checks run inside the
-- SECURITY DEFINER body: private busy data and other planners' bookings are
-- consulted but never returned; the vendor is simply omitted. When p_on_date is
-- null the E10 behavior is unchanged.
--
-- The new param is added at the END with a default, but adding it makes a new
-- 8-arg signature: CREATE OR REPLACE would create a SECOND overload, and a 7-arg
-- call (the current client) would then match BOTH (the 8-arg's default also
-- matches) → PostgREST "could not choose the best candidate". So drop the old
-- 7-arg function first, leaving exactly one function the 7-arg client still binds
-- to (p_on_date defaulting null).

drop function if exists public.search_vendors(
    text, text, double precision, double precision, double precision, int, int
);

create or replace function public.search_vendors(
    p_query      text             default null,
    p_category   text             default null,
    p_lat        double precision default null,
    p_lng        double precision default null,
    p_radius_km  double precision default null,
    p_limit      int              default 20,
    p_offset     int              default 0,
    p_on_date    date             default null
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
          -- Availability (E18): when a date is given, drop vendors who are
          -- manually busy that day. Reads PRIVATE vendor_busy_dates definer-side;
          -- nothing about it is returned, only the omission.
          and (
              p_on_date is null
              or not exists (
                  select 1
                  from public.vendor_busy_dates bd
                  where bd.profile_id = vp.profile_id
                    and bd.deleted_at is null
                    and bd.busy_date = p_on_date
              )
          )
          -- Availability (E18): and drop vendors booked on a Shift event that day
          -- (claimed event_vendors row on an event dated p_on_date). Reads other
          -- planners' events definer-side; only the omission is observable.
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

comment on function public.search_vendors(text, text, double precision, double precision, double precision, int, int, date)
    is 'Vendor directory search over listed, non-deleted vendor_profiles: ILIKE/'
       'trigram name match, skills overlap, category equality, haversine radius '
       '(no PostGIS). Excludes blocked vendors both directions. E18: p_on_date '
       'excludes vendors manually busy OR booked (claimed event) that day, checked '
       'definer-side so private data never leaks. SECURITY DEFINER; ordered by '
       'rating_avg desc nulls last, events_completed_count desc.';

-- Authenticated-only; never anon / public (new 8-arg signature).
revoke all on function public.search_vendors(text, text, double precision, double precision, double precision, int, int, date) from public;
revoke all on function public.search_vendors(text, text, double precision, double precision, double precision, int, int, date) from anon;
grant execute on function public.search_vendors(text, text, double precision, double precision, double precision, int, int, date) to authenticated;
