-- SHIFT-642: upsert_device_token() — register the caller's APNs token
--
-- device_tokens has RLS enabled with NO table policies: it carries APNs routing
-- data, is excluded from the realtime publication, and must never be read or
-- written directly by a client. Clients register exclusively through this RPC.
--
-- Behaviour:
--   * profile_id is taken from the caller's verified auth.uid() — a client can
--     never register a token under another profile.
--   * Upserts on the unique apns_token, re-keying profile_id/environment when a
--     device is handed to a new user (account switch on the same hardware).
--   * updated_at is bumped by the existing set_updated_at trigger.
--
-- Security notes mirror can_access_event() (SHIFT-557):
--   SECURITY DEFINER     — runs as owner so it can write the deny-by-default table.
--   set search_path = '' — prevents search_path hijacking; refs are schema-qualified.
-- Edge Functions (SHIFT-638) read device_tokens with the service role (bypasses
-- RLS), so no client SELECT policy is required.

create or replace function public.upsert_device_token(
    p_apns_token text,
    p_environment text
)
returns void
language sql
security definer
set search_path = ''
as $$
    insert into public.device_tokens (profile_id, apns_token, environment)
    values (auth.uid(), p_apns_token, p_environment)
    on conflict (apns_token) do update
        set profile_id  = excluded.profile_id,
            environment = excluded.environment;
$$;

revoke all on function public.upsert_device_token(text, text) from public, anon;
grant execute on function public.upsert_device_token(text, text) to authenticated;

comment on function public.upsert_device_token(text, text)
    is 'Registers the caller''s APNs token in device_tokens (SHIFT-642). '
       'profile_id is derived from auth.uid(); upserts on the unique apns_token, '
       're-keying owner/environment on account switch. SECURITY DEFINER because '
       'device_tokens is deny-by-default (no client table policies).';
