-- SHIFT-668: durable record of Edge Function / APNs delivery failures.
--
-- The shift-notify Edge Function writes a row here (service role) whenever a
-- push cannot be delivered: missing APNs secrets, token-lookup errors, APNs
-- rejections (4xx/5xx other than the routine 410 token reaping), or an
-- unhandled exception. pg_net trigger responses are fire-and-forget, so without
-- this table a production push outage is invisible — this is the queryable
-- alert source for the launch-readiness runbook.

create table if not exists public.notification_failures (
    id uuid primary key default gen_random_uuid(),
    occurred_at timestamptz not null default now(),
    kind text not null,            -- shift | assignment | golive | unknown
    reason text not null,          -- secrets_missing | token_query_failed | apns_rejected | exception
    detail text,                   -- error message / APNs response body
    apns_status int,               -- APNs HTTP status when applicable
    event_id uuid,                 -- best-effort context (no FK: events may be purged)
    profile_id uuid
);

comment on table public.notification_failures is
    'Edge Function / APNs delivery failures (SHIFT-668). Written by shift-notify with the service role; alert source for sync-health monitoring.';

-- Service-role only: RLS enabled with no policies means anon/authenticated
-- clients can neither read nor write; the Edge Function uses the service role,
-- which bypasses RLS.
alter table public.notification_failures enable row level security;

-- The alert query scans recent failures.
create index if not exists notification_failures_occurred_at_idx
    on public.notification_failures (occurred_at desc);
