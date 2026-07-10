-- Marketplace discovery — put the vendor's WORK on the directory card.
--
-- Today `vendor_search_result` carries only `avatar_url`, so every discovery card
-- (home carousels, search results, saved list) can show nothing but the vendor's
-- profile photo — a face. For event vendors the portfolio *is* the product, so we
-- return a cover image: the vendor's first portfolio photo/video by their own
-- `sort_order`. The client renders it as the card hero and demotes the avatar to a
-- small circular attribution mark.
--
-- `vendor_search_result` is the return type of two live functions, so the type is
-- dropped and recreated together with them. (The older 7- and 8-arg
-- `search_vendors` signatures were already dropped by the p_on_date and
-- marketplace_pro migrations; only the 9-arg one and `get_saved_vendors` remain.)
-- All DDL here is transactional, so there is no window where the RPCs are missing.
--
-- New attributes, appended so ordinal positions of existing fields are unchanged:
--   cover_path text  — storage path in the `vendor-portfolio` bucket, or NULL
--   cover_kind text  — 'photo' | 'video', so the client can render a video poster

drop function if exists public.search_vendors(
    text, text, double precision, double precision, double precision, int, int, date, text
);
drop function if exists public.get_saved_vendors();
drop type if exists public.vendor_search_result;

create type public.vendor_search_result as (
    profile_id              uuid,
    display_name            text,
    business_name           text,
    bio                     text,
    avatar_url              text,
    category                text,
    skills                  text[],
    service_area            text,
    latitude                double precision,
    longitude               double precision,
    service_radius_km       double precision,
    events_completed_count  int,
    rating_avg              numeric(3,2),
    rating_count            int,
    distance_km             double precision,
    -- Discovery cover (the vendor's own first portfolio item).
    cover_path              text,
    cover_kind              text
);

-- Makes the per-vendor cover lookup an index-only hop instead of a scan.
create index if not exists portfolio_items_cover_idx
    on public.portfolio_items (profile_id, sort_order, created_at)
    where deleted_at is null and storage_path is not null and kind in ('photo', 'video');

-- ─────────────────────────────────────────────────────────────────────────────
-- search_vendors — unchanged behaviour, plus the cover columns.
-- ─────────────────────────────────────────────────────────────────────────────
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
            end as distance_km,
            cover.storage_path as cover_path,
            cover.kind         as cover_kind
        from public.vendor_profiles vp
        join public.public_profiles pp on pp.id = vp.profile_id
        -- The vendor's own first portfolio item is the card hero.
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
        profile_id, display_name, business_name, bio, avatar_url,
        category, skills, service_area, latitude, longitude, service_radius_km,
        events_completed_count, rating_avg, rating_count, distance_km,
        cover_path, cover_kind
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
    is 'Vendor directory search (E10/E18/E22 + cover image). Filters: name/skills, '
       'category, haversine radius, p_on_date availability. p_sort: rating|booked|'
       'nearest. Returns the vendor''s first portfolio photo/video as cover_path/'
       'cover_kind for the card hero. SECURITY DEFINER; blocked vendors excluded '
       'both directions.';

revoke all on function public.search_vendors(text, text, double precision, double precision, double precision, int, int, date, text) from public, anon;
grant execute on function public.search_vendors(text, text, double precision, double precision, double precision, int, int, date, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- get_saved_vendors — unchanged behaviour, plus the cover columns.
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
        null::double precision as distance_km,
        cover.storage_path as cover_path,
        cover.kind         as cover_kind
    from public.saved_vendors sv
    join public.vendor_profiles vp on vp.profile_id = sv.vendor_profile_id
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
    is 'The caller''s saved + listed vendors as directory cards (E22), newest first, '
       'including the cover image used by the card hero.';

revoke all on function public.get_saved_vendors() from public, anon;
grant execute on function public.get_saved_vendors() to authenticated;
