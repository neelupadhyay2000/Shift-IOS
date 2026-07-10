-- ─────────────────────────────────────────────────────────────────────────────
-- Community Templates — the "Official" provenance flag (E23)
--
-- WHY THIS EXISTS
--   `source_event_completed` is the "Verified — run in Shift" seal, and it means
--   exactly one thing: this run-sheet came from a completed event the author
--   actually ran in the app. First-party sample templates published by SHIFT have
--   not been run by anyone, so they must never carry that seal — doing so would
--   make the App Store copy ("a profile can't be faked") false and would drain the
--   seal of meaning for every real template that earns it later.
--
--   `is_official` is the honest badge for that content: it claims authorship, not
--   provenance. The two are independent — an official template CAN also be
--   verified, if SHIFT publishes one from an event it genuinely ran.
--
-- WHO CAN SET IT
--   Nobody, through any client path. `publish_community_template` does not touch
--   the column, so every user-published row takes the `false` default. The author
--   UPDATE policy's immutability guard is extended below to freeze it, otherwise
--   an author could simply UPDATE their own row and declare themselves official.
--   It is set only by the operator, via supabase/seed/community_templates_seed.sql.
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.community_templates
    add column is_official boolean not null default false;

comment on column public.community_templates.is_official
    is 'First-party template published by SHIFT. An authorship claim, NOT a '
       'provenance claim — orthogonal to source_event_completed ("run in Shift"). '
       'Never writable by a client: publish_community_template ignores it and the '
       'author UPDATE policy freezes it. Set only by the operator seed script.';

-- Browse lists official templates alongside the rest; this partial index keeps the
-- "official only" filter (if the UI ever adds one) off a sequential scan.
create index community_templates_official_idx
    on public.community_templates (created_at desc)
    where is_official and is_published and deleted_at is null;

-- ─────────────────────────────────────────────────────────────────────────────
-- Extend the immutability guard.
--
-- The original policy froze author_id / created_at / blocks / block_count /
-- source_event_completed / times_applied. `is_official` joins them: it is a claim
-- about who wrote the template, and a client must not be able to assert it.
-- Only name / description / category / is_published / deleted_at stay mutable.
-- ─────────────────────────────────────────────────────────────────────────────
drop policy "community_templates_author_update" on public.community_templates;

create policy "community_templates_author_update" on public.community_templates
    for update
    to authenticated
    using (author_id = auth.uid())
    with check (
        author_id = auth.uid()
        and (
            select
                stored.author_id              = community_templates.author_id
                and stored.created_at         = community_templates.created_at
                and stored.blocks             = community_templates.blocks
                and stored.block_count        = community_templates.block_count
                and stored.source_event_completed = community_templates.source_event_completed
                and stored.times_applied      = community_templates.times_applied
                and stored.is_official        = community_templates.is_official
            from public.community_templates stored
            where stored.id = community_templates.id
        )
    );

-- ─────────────────────────────────────────────────────────────────────────────
-- search_community_templates() — republished with `is_official` in the projection.
--
-- DROP first: `create or replace` cannot change a function's `returns table`
-- shape. Body is otherwise byte-identical to 20260709160000 (which added the
-- `p.deleted_at is null` join filter so an ejected author's content leaves the
-- directory with them).
-- ─────────────────────────────────────────────────────────────────────────────
drop function if exists public.search_community_templates(text, text, text, integer, integer);

create function public.search_community_templates(
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
    is_official            boolean,
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
        ct.is_official,
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
    is 'Paginated, filtered browse of published community templates with the '
       'author display name, the "run in Shift" verified flag, and the "official" '
       'authorship flag. Excludes soft-deleted templates and soft-deleted authors.';

-- Re-apply the grants. `create function` grants EXECUTE to PUBLIC by default, and
-- anon inherits it — so revoking from `anon` alone would leave the function
-- callable by unauthenticated clients. Must revoke from `public` too, exactly as
-- 20260625120000 and 20260709160000 did.
revoke all on function public.search_community_templates(text, text, text, integer, integer) from public, anon;
grant execute on function public.search_community_templates(text, text, text, integer, integer) to authenticated;
