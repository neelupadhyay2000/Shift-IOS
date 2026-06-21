-- Marketplace Directory (vendor discovery) — Story 5: content_reports (UGC safety)
--
-- Apple Guideline 1.2: any app with user-generated content must let users report
-- objectionable content and block abusive users, with a moderation path. Blocking
-- already lives in user_blocks (created with search_vendors in 20260620150000);
-- this migration adds the report sink + its moderation workflow columns.
--
-- Reports land here and are triaged out-of-band (see docs/marketplace-moderation-
-- runbook.md): the moderator works the table via the Supabase dashboard
-- (service_role bypasses RLS); end users may only file and read their OWN reports.

create table public.content_reports (
    id            uuid primary key default gen_random_uuid(),
    reporter_id   uuid not null references public.profiles(id) on delete cascade,

    -- What was reported. content_id is a soft reference (no FK) because it spans
    -- several tables (and future message rows) — the moderator resolves it by type.
    content_type  text not null check (content_type in
                      ('vendor_profile', 'portfolio_item', 'review', 'message')),
    content_id    uuid not null,
    reason        text not null default '',

    -- Moderation workflow (worked via dashboard / service_role).
    status        text not null default 'pending'
                      check (status in ('pending', 'actioned', 'dismissed')),
    created_at    timestamptz not null default now(),
    resolved_at   timestamptz,

    -- One report per reporter per piece of content (idempotent; blocks dupe spam).
    constraint content_reports_unique_per_reporter
        unique (reporter_id, content_type, content_id)
);

comment on table public.content_reports
    is 'UGC abuse reports (Apple Guideline 1.2). Users file/read only their own '
       'rows (insert/select-own RLS); moderators triage via service_role. '
       'content_id is a typed soft reference across vendor_profiles/portfolio_items'
       '/reviews/messages. See docs/marketplace-moderation-runbook.md.';

-- Moderation triage queue (oldest pending first).
create index content_reports_triage_idx
    on public.content_reports (status, created_at);

-- "Show me everything reported against this content" for the moderator.
create index content_reports_content_idx
    on public.content_reports (content_type, content_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- RLS: file-own + read-own only. No user update/delete (reports are immutable
-- once filed; the moderator mutates status via service_role).
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.content_reports enable row level security;

create policy "content_reports_insert_own" on public.content_reports
    for insert
    to authenticated
    with check (reporter_id = auth.uid());

create policy "content_reports_select_own" on public.content_reports
    for select
    to authenticated
    using (reporter_id = auth.uid());

revoke all on public.content_reports from anon;
