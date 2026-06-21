-- Marketplace Trust (E17) — Story 3: get_vendor_reviews read RPC
--
-- The reviews list on the public profile needs each review's reviewer display
-- name AND the worked event's date. The vendor_reviews public_select RLS already
-- exposes the review body/rating, but the reviewer's identity lives on profiles
-- and the event date on events — both behind RLS the viewer doesn't have. This
-- SECURITY DEFINER RPC joins them past RLS (the same pattern as
-- get_portfolio_event_summaries), scoped to LISTED vendors only, and drops
-- reviews involving a user the caller has blocked (either direction), matching
-- search_vendors.

create or replace function public.get_vendor_reviews(
    p_vendor_profile_id uuid,
    p_limit  int default 20,
    p_offset int default 0
)
returns table (
    id            uuid,
    event_id      uuid,
    reviewer_id   uuid,
    rating        smallint,
    body          text,
    created_at    timestamptz,
    reviewer_name text,
    event_title   text,
    event_date    timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
    select
        r.id,
        r.event_id,
        r.reviewer_id,
        r.rating,
        r.body,
        r.created_at,
        coalesce(
            nullif(btrim(p.business_name), ''),
            nullif(btrim(p.display_name), ''),
            'Planner'
        )                                  as reviewer_name,
        e.title                            as event_title,
        e.date                             as event_date
      from public.vendor_reviews r
      join public.vendor_profiles vp on vp.profile_id = r.vendor_profile_id
      join public.profiles p         on p.id = r.reviewer_id
      left join public.events e      on e.id = r.event_id
     where r.vendor_profile_id = p_vendor_profile_id
       and r.deleted_at is null
       and vp.is_listed
       and vp.deleted_at is null
       -- Block exclusion, both directions (mirrors search_vendors).
       and not exists (
           select 1
           from public.user_blocks b
           where (b.blocker_id = auth.uid() and b.blocked_id = r.reviewer_id)
              or (b.blocker_id = r.reviewer_id and b.blocked_id = auth.uid())
       )
     order by r.created_at desc
     limit  least(greatest(coalesce(p_limit, 20), 1), 50)
     offset greatest(coalesce(p_offset, 0), 0);
$$;

comment on function public.get_vendor_reviews(uuid, int, int)
    is 'Paginated reviews for a LISTED vendor with reviewer display name + worked '
       'event title/date joined past RLS (definer). Excludes reviews involving a '
       'user the caller blocked. Newest first.';

revoke all on function public.get_vendor_reviews(uuid, int, int) from public, anon;
grant execute on function public.get_vendor_reviews(uuid, int, int) to authenticated;
