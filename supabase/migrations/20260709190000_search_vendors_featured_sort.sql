-- Marketplace home ordering: a `featured` sort.
--
-- The home page grouped vendors into per-category carousels, which imposed an
-- ordering ("by vendor type") nobody asked for and buried good vendors under a
-- category header. The new page is: a few **featured** vendors, then everything
-- else ordered by completed events (`p_sort = 'booked'`, which already exists).
--
-- WHY NOT ORDER FEATURED BY rating_avg
-- A raw average is meaningless at low volume: a vendor with a single 5.0 review
-- outranks one with 4.9 across 100. So `featured` uses a **Bayesian shrunk
-- rating** (the "true Bayesian estimate" / IMDb weighted rating):
--
--     score = (v / (v + m)) * R  +  (m / (v + m)) * C
--
--   v = the vendor's rating_count
--   R = the vendor's rating_avg
--   m = the prior weight (5 reviews' worth of scepticism)
--   C = the global mean rating across reviewed, listed vendors
--
-- A vendor with few reviews is pulled toward the global mean; one with many keeps
-- their own average. Worked example (C ≈ 4.5):
--     5.0 from   1 review  → (1/6)*5.0 + (5/6)*4.5 = 4.58
--     4.9 from 100 reviews → (100/105)*4.9 + (5/105)*4.5 = 4.88   ← correctly wins
--
-- UNREVIEWED VENDORS score 0, not C. Scoring them at the mean would let a brand-new
-- vendor with nothing outrank a genuinely-rated 4.2. They fall through to the
-- shared tiebreakers instead, so at launch — when nobody has reviews — `featured`
-- degrades gracefully to "most events completed", which is exactly the trust story
-- the marketplace already tells.
--
-- Signature and return type are unchanged, so this is a plain `create or replace`.

create or replace function public.search_vendors(
    p_query      text             default null,
    p_category   text             default null,
    p_lat        double precision default null,
    p_lng        double precision default null,
    p_radius_km  double precision default null,
    p_limit      int              default 20,
    p_offset     int              default 0,
    p_on_date    date             default null,
    p_sort       text             default null   -- 'rating' | 'booked' | 'nearest' | 'featured'
)
returns setof public.vendor_search_result
language sql
stable
security definer
set search_path = ''
as $$
    with prior as (
        -- The global mean rating (C), over listed vendors that actually have
        -- reviews. Computed once per call, not per row.
        select coalesce(
                   avg(vp.rating_avg) filter (where vp.rating_count > 0),
                   0
               )::numeric as global_avg
        from public.vendor_profiles vp
        where vp.is_listed and vp.deleted_at is null
    ),
    matched as (
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
            end as distance_km,
            cover.storage_path as cover_path,
            cover.kind         as cover_kind
        from public.vendor_profiles vp
        join public.public_profiles pp on pp.id = vp.profile_id
        left join lateral (
            select pi.storage_path, pi.kind
            from public.portfolio_items pi
            where pi.profile_id = vp.profile_id
              and pi.deleted_at is null
              and pi.storage_path is not null
              and pi.kind in ('photo', 'video')
            order by pi.sort_order asc, pi.created_at asc
            limit 1
        ) cover on true
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
        m.profile_id, m.display_name, m.business_name, m.bio, m.avatar_url,
        m.category, m.skills, m.service_area, m.latitude, m.longitude, m.service_radius_km,
        m.events_completed_count, m.rating_avg, m.rating_count, m.distance_km,
        m.cover_path, m.cover_kind
    from matched m
    cross join prior
    where p_lat is null or p_lng is null or p_radius_km is null
       or (m.distance_km is not null and m.distance_km <= p_radius_km)
    order by
        -- 'featured': Bayesian shrunk rating. Unreviewed vendors score 0 and fall
        -- through to the tiebreakers (i.e. most-booked) rather than to the mean.
        case when p_sort = 'featured' then
            case when m.rating_count > 0
                 then (m.rating_count::numeric / (m.rating_count + 5))
                        * coalesce(m.rating_avg, 0)
                    + (5::numeric / (m.rating_count + 5)) * prior.global_avg
                 else 0
            end
        end desc nulls last,
        -- 'nearest' only meaningful when a point was supplied; nulls sort last.
        case when p_sort = 'nearest' then m.distance_km end asc nulls last,
        case when p_sort = 'booked'  then m.events_completed_count end desc nulls last,
        -- default + 'rating': rating first, then most-booked (the E10 ordering).
        m.rating_avg desc nulls last,
        m.events_completed_count desc,
        m.profile_id
    limit  least(greatest(coalesce(p_limit, 20), 1), 50)
    offset greatest(coalesce(p_offset, 0), 0);
$$;

comment on function public.search_vendors(text, text, double precision, double precision, double precision, int, int, date, text)
    is 'Vendor directory search (E10/E18/E22 + cover image). Filters: name/skills, '
       'category, haversine radius, p_on_date availability. p_sort: rating|booked|'
       'nearest|featured. ''featured'' ranks by a Bayesian shrunk rating (prior m=5, '
       'global mean C) so a single 5-star review cannot outrank a well-reviewed '
       'vendor; unreviewed vendors score 0 and fall back to most-booked. Returns the '
       'vendor''s first portfolio photo/video as cover_path/cover_kind. SECURITY '
       'DEFINER; blocked vendors excluded both directions.';

revoke all on function public.search_vendors(text, text, double precision, double precision, double precision, int, int, date, text) from public, anon;
grant execute on function public.search_vendors(text, text, double precision, double precision, double precision, int, int, date, text) to authenticated;
