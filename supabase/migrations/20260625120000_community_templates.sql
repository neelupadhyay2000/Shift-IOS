-- Community Templates (E23) — shared, browsable event run-sheets.
--
-- Fully free: any authenticated user can publish (via the gated RPC) and
-- browse / apply. The publish path is the SECURITY DEFINER publish_community_template
-- RPC — there is deliberately NO direct INSERT policy, mirroring vendor_reviews —
-- so author_id and the "verified" provenance flag cannot be spoofed by the client.
--
-- "Verified — run in Shift" badge: source_event_completed is set TRUE *only* when
-- the publish RPC confirms the supplied source event is a completed event owned by
-- the caller. The client cannot set it directly.
--
-- Post-moderation: rows are live the moment they publish. They are reportable UGC
-- (content_reports gains a 'community_template' content_type below), the author can
-- unpublish / soft-delete their own, and blocked authors are filtered client-side
-- (same posture as the rest of the marketplace).
--
-- Online-only by design: NOT part of the SwiftData / Outbox sync stack and NOT in
-- the realtime publication, exactly like vendor_profiles / vendor_reviews.

-- ─────────────────────────────────────────────────────────────────────────────
-- Table
-- ─────────────────────────────────────────────────────────────────────────────
create table public.community_templates (
    id                      uuid primary key default gen_random_uuid(),
    author_id               uuid not null references public.profiles(id) on delete cascade,

    name                    text not null check (char_length(name) between 1 and 120),
    description             text not null default '' check (char_length(description) <= 1000),
    category                text not null
                              check (category in ('wedding', 'corporate', 'social', 'photography')),

    -- The iOS [TemplateBlock] array, byte-for-byte as the Template JSON encodes it
    -- (relative offsets, so the template stays date-independent).
    blocks                  jsonb not null,
    block_count             integer not null default 0 check (block_count >= 0),

    -- Trust signal: true only when published from a completed, caller-owned event.
    source_event_completed  boolean not null default false,
    -- Popularity: bumped by apply_community_template on every apply (any authed user).
    times_applied           integer not null default 0 check (times_applied >= 0),

    is_published            boolean not null default true,

    created_at              timestamptz not null default now(),
    updated_at              timestamptz not null default now(),
    deleted_at              timestamptz
);

comment on table public.community_templates
    is 'Community-shared event templates (E23). Written ONLY via publish_community_template '
       '(no direct INSERT policy); source_event_completed is verified server-side. Online-only '
       '(not in the SwiftData sync stack or realtime publication). Reportable UGC via '
       'content_reports. RLS: public_select of published, non-deleted rows + author self-manage.';

-- ─────────────────────────────────────────────────────────────────────────────
-- Indexes
-- ─────────────────────────────────────────────────────────────────────────────
-- Browse, newest-first (partial: only the rows the directory ever lists).
create index community_templates_browse_idx
    on public.community_templates (created_at desc)
    where is_published and deleted_at is null;

-- Browse, most-applied-first (the "Popular" sort).
create index community_templates_popular_idx
    on public.community_templates (times_applied desc)
    where is_published and deleted_at is null;

-- The author's own "Published by you" list (includes unpublished / soft-deleted).
create index community_templates_author_idx
    on public.community_templates (author_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- updated_at bump — shared trigger function (SHIFT-556).
-- ─────────────────────────────────────────────────────────────────────────────
create trigger set_updated_at
    before update on public.community_templates
    for each row execute function public.set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- RLS — note: deliberately NO insert policy (see publish_community_template).
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.community_templates enable row level security;

-- Directory: any authenticated user reads published, non-deleted templates.
-- Author blocking is applied client-side, matching the rest of the marketplace.
create policy "community_templates_public_select" on public.community_templates
    for select
    to authenticated
    using (is_published and deleted_at is null);

-- Author: read own rows (incl. unpublished / soft-deleted) for the management list.
create policy "community_templates_author_select" on public.community_templates
    for select
    to authenticated
    using (author_id = auth.uid());

-- Author: unpublish / edit metadata / soft-delete own rows. The immutability guard
-- freezes the provenance + identity columns so only name/description/category/
-- is_published/deleted_at can move — blocks, the verified flag, and times_applied
-- (bumped exclusively by the SECURITY DEFINER apply RPC) stay honest.
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
            from public.community_templates stored
            where stored.id = community_templates.id
        )
    );

-- Authenticated-only marketplace: revoke the Data API's auto-grants to anon.
revoke all on public.community_templates from anon;

-- ─────────────────────────────────────────────────────────────────────────────
-- publish_community_template() — the ONLY write path into community_templates.
--
-- SECURITY DEFINER so it can INSERT past the (intentionally absent) insert policy.
-- It stamps author_id = auth.uid() and computes the verified badge itself: the flag
-- is TRUE only when p_source_event_id is a completed event owned by the caller, so
-- the client can never fake "Run in Shift". search_path = '' with fully-qualified
-- names, per repo convention.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.publish_community_template(
    p_name              text,
    p_description       text,
    p_category          text,
    p_blocks            jsonb,
    p_block_count       integer,
    p_source_event_id   uuid default null
)
returns setof public.community_templates
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_uid      uuid := auth.uid();
    v_verified boolean := false;
begin
    if v_uid is null then
        raise exception 'publish_community_template: not authenticated'
            using errcode = '28000';
    end if;

    if p_category not in ('wedding', 'corporate', 'social', 'photography') then
        raise exception 'publish_community_template: invalid category %', p_category
            using errcode = '22023';
    end if;

    -- Verified badge: only when the source is a completed, caller-owned event.
    if p_source_event_id is not null then
        v_verified := exists (
            select 1
            from public.events e
            where e.id = p_source_event_id
              and e.owner_id = v_uid
              and e.status = 'completed'
              and e.deleted_at is null
        );
    end if;

    return query
    insert into public.community_templates
        (author_id, name, description, category, blocks, block_count, source_event_completed)
    values
        (v_uid, p_name, coalesce(p_description, ''), p_category,
         p_blocks, greatest(coalesce(p_block_count, 0), 0), v_verified)
    returning *;
end;
$$;

comment on function public.publish_community_template(text, text, text, jsonb, integer, uuid)
    is 'The only write path into community_templates. Stamps author_id = auth.uid() and '
       'sets source_event_completed TRUE only when p_source_event_id is a completed, '
       'caller-owned event. SECURITY DEFINER, authenticated-only.';

revoke all on function public.publish_community_template(text, text, text, jsonb, integer, uuid) from public, anon;
grant execute on function public.publish_community_template(text, text, text, jsonb, integer, uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- apply_community_template() — bump the popularity counter on apply.
--
-- SECURITY DEFINER so any authenticated applier can increment a template they don't
-- own (the author-only UPDATE policy would otherwise block it). Only published,
-- non-deleted rows count. Returns the new total, or NULL if the row isn't applyable.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.apply_community_template(p_template_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_uid   uuid := auth.uid();
    v_count integer;
begin
    if v_uid is null then
        raise exception 'apply_community_template: not authenticated'
            using errcode = '28000';
    end if;

    update public.community_templates
       set times_applied = times_applied + 1
     where id = p_template_id
       and is_published
       and deleted_at is null
    returning times_applied into v_count;

    return v_count;
end;
$$;

comment on function public.apply_community_template(uuid)
    is 'Increments times_applied for a published, non-deleted community template and '
       'returns the new total (NULL if not applyable). SECURITY DEFINER so any '
       'authenticated applier can bump a template they do not own.';

revoke all on function public.apply_community_template(uuid) from public, anon;
grant execute on function public.apply_community_template(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- search_community_templates() — the browse read (with author name resolved).
--
-- Returns published, non-deleted templates filtered by optional category + keyword,
-- ordered by 'newest' or 'popular' (default). SECURITY DEFINER + a profiles join so
-- the author display name comes back in one round-trip (mirrors get_vendor_reviews).
-- p_limit is clamped to [1, 100]. Blocked-author exclusion is applied client-side.
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
    is 'Browse read for community templates: published + non-deleted, optional category '
       '+ keyword filter, ordered newest/popular, author name resolved via profiles. '
       'SECURITY DEFINER, authenticated-only.';

revoke all on function public.search_community_templates(text, text, text, integer, integer) from public, anon;
grant execute on function public.search_community_templates(text, text, text, integer, integer) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- content_reports: make community templates reportable UGC.
-- Extend the content_type CHECK (Apple Guideline 1.2 — report/flag for this surface).
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.content_reports
    drop constraint content_reports_content_type_check;

alter table public.content_reports
    add constraint content_reports_content_type_check
    check (content_type in
        ('vendor_profile', 'portfolio_item', 'review', 'message', 'community_template'));
