-- Marketplace (E24 follow-up) — ejected users must disappear from public reads.
--
-- BUG
-- `public_profiles` (the view every directory read is supposed to join) filters
-- `deleted_at is null`, which is what makes `search_vendors` correctly hide a
-- user we have ejected. But two SECURITY DEFINER RPCs join `public.profiles`
-- *directly* and never filter the author's tombstone:
--
--   * search_community_templates → an ejected author's templates stayed publicly
--     listed, with their name attached.
--   * get_vendor_reviews        → an ejected reviewer's name stayed on the
--     reviews of every listed vendor they had reviewed.
--
-- This contradicts the Terms ("we will remove offending content and eject
-- offending users") and the moderation runbook, which both promise that setting
-- `profiles.deleted_at` removes a user from the marketplace everywhere.
--
-- Self-service deletion was never affected: `delete_account()` hard-deletes the
-- `auth.users` row, which cascades `profiles` → `community_templates` /
-- `vendor_reviews`, so the rows are gone rather than merely hidden. The defect
-- only bit the *moderation* path — the one Guideline 1.2 cares about.
--
-- FIX
-- Add `and p.deleted_at is null` to both. Bodies are otherwise reproduced
-- verbatim from 20260625120000_community_templates.sql and
-- 20260621150000_get_vendor_reviews.sql; the return signatures are unchanged so
-- `create or replace` is a drop-in.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. search_community_templates — hide templates authored by an ejected user.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.search_community_templates(
    p_category text default null,
    p_query    text default '',
    p_sort     text default 'popular',
    p_limit    integer default 30,
    p_offset   integer default 0
)
returns table (
    id                     uuid,
    author_id              uuid,
    author_name            text,
    name                   text,
    description            text,
    category               text,
    blocks                 jsonb,
    block_count            integer,
    source_event_completed boolean,
    times_applied          integer,
    created_at             timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
    select
        ct.id,
        ct.author_id,
        coalesce(
            nullif(btrim(p.business_name), ''),
            nullif(btrim(p.display_name), ''),
            'Shift Member'
        )                              as author_name,
        ct.name,
        ct.description,
        ct.category,
        ct.blocks,
        ct.block_count,
        ct.source_event_completed,
        ct.times_applied,
        ct.created_at
      from public.community_templates ct
      join public.profiles p on p.id = ct.author_id
     where ct.is_published
       and ct.deleted_at is null
       -- An ejected/soft-deleted author's content leaves the directory with them.
       and p.deleted_at is null
       and (p_category is null or ct.category = p_category)
       and (
            coalesce(btrim(p_query), '') = ''
            or ct.name ilike '%' || btrim(p_query) || '%'
            or ct.description ilike '%' || btrim(p_query) || '%'
       )
     order by
        -- 'newest' → created_at first; anything else → popularity first.
        (case when p_sort = 'newest' then ct.created_at else to_timestamp(0) end) desc,
        ct.times_applied desc,
        ct.created_at desc
     limit greatest(1, least(coalesce(p_limit, 30), 100))
    offset greatest(0, coalesce(p_offset, 0));
$$;

comment on function public.search_community_templates(text, text, text, integer, integer)
    is 'Browse read for community templates: published + non-deleted, authored by a '
       'non-deleted user, optional category + keyword filter, ordered newest/popular, '
       'author name resolved via profiles. SECURITY DEFINER, authenticated-only.';

revoke all on function public.search_community_templates(text, text, text, integer, integer) from public, anon;
grant execute on function public.search_community_templates(text, text, text, integer, integer) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. get_vendor_reviews — hide reviews written by an ejected user.
-- ─────────────────────────────────────────────────────────────────────────────
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
       -- An ejected/soft-deleted reviewer's review leaves the profile with them.
       and p.deleted_at is null
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
       'event title/date joined past RLS (definer). Excludes reviews written by a '
       'deleted/ejected user, and reviews involving a user the caller blocked. '
       'Newest first.';

revoke all on function public.get_vendor_reviews(uuid, int, int) from public, anon;
grant execute on function public.get_vendor_reviews(uuid, int, int) to authenticated;
