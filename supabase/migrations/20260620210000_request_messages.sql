-- Marketplace Request Chat (E12) — Story 1: request_messages
--
-- Lightweight realtime chat scoped to a single service_request (not general DMs).
-- Both participants — the request's planner and vendor — read and post; access is
-- gated by can_access_request(), the request-scoped mirror of can_access_event().
--
-- In the realtime publication so messages stream to the other device; RLS scopes
-- broadcasts per subscriber (only rows the connected user can SELECT are sent),
-- exactly like the event collaboration tables.

create table public.request_messages (
    id          uuid primary key default gen_random_uuid(),
    request_id  uuid not null references public.service_requests(id) on delete cascade,
    sender_id   uuid not null references public.profiles(id) on delete cascade,
    body        text not null check (char_length(body) <= 4000),

    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now(),
    deleted_at  timestamptz
);

comment on table public.request_messages
    is 'Per-service-request chat (E12). Participants (request planner + vendor) read'
       '/post, gated by can_access_request(). In the realtime publication; RLS '
       'scopes broadcasts per subscriber. Reportable UGC (content_reports).';

-- Thread fetch / realtime ordering.
create index request_messages_thread_idx
    on public.request_messages (request_id, created_at);

-- set_updated_at trigger (shared, SHIFT-556).
create trigger set_updated_at
    before update on public.request_messages
    for each row execute function public.set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- can_access_request() — request-scoped access predicate (mirror of
-- can_access_event() in 20260604173402). True when the caller is the request's
-- planner or the targeted vendor. SECURITY DEFINER so it reads service_requests
-- regardless of the caller's own RLS; search_path = '' (schema-qualified).
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.can_access_request(rid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.service_requests r
        where r.id = rid
          and r.deleted_at is null
          and (r.planner_id = auth.uid() or r.vendor_profile_id = auth.uid())
    )
$$;

comment on function public.can_access_request(uuid)
    is 'Returns true if auth.uid() is the request''s planner or vendor. Shared '
       'access predicate for request_messages RLS (mirror of can_access_event).';

-- ─────────────────────────────────────────────────────────────────────────────
-- RLS: both participants read; sender posts as themselves. No user update/delete
-- (messages are immutable; deleted_at is for moderation via service_role).
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.request_messages enable row level security;

create policy "request_messages_select" on public.request_messages
    for select
    to authenticated
    using (public.can_access_request(request_id));

create policy "request_messages_insert" on public.request_messages
    for insert
    to authenticated
    with check (
        sender_id = auth.uid()
        and public.can_access_request(request_id)
    );

revoke all on public.request_messages from anon;

-- Realtime: stream messages to the other participant's thread channel.
alter publication supabase_realtime add table public.request_messages;
