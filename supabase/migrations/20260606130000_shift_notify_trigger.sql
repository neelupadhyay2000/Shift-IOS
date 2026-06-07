-- SHIFT-643: trigger that invokes the shift-notify Edge Function on a shift
--
-- A shift's only server-side effect is the planner's post-shift reset
-- (SHIFT-634): UPDATE event_vendors SET has_acknowledged_latest_shift = false,
-- pending_shift_delta = <drift> WHERE id = <vendor>. That pending_shift_delta
-- write is therefore the canonical "a shift happened for this vendor" signal, so
-- we trigger on it directly — no new table, no client changes.
--
-- The trigger only fires the HTTP call; the Edge Function (SHIFT-644) owns the
-- authoritative threshold check (per-vendor notification_threshold + a global
-- floor), resolves the vendor's device_tokens, and sends APNs. Firing per row
-- gives exactly one invocation per affected vendor per shift.
--
-- Auth/URL are read from Vault (per-project, never committed): set once per
-- project with vault.create_secret(...) — see SHIFT-643 deploy notes. Missing
-- secrets degrade gracefully (warn + no-op) so shifts never fail on this path.

-- pg_net provides net.http_post for async outbound HTTP from Postgres. On Supabase
-- this can also be enabled via Dashboard → Database → Extensions; idempotent here.
create extension if not exists pg_net;

-- ─────────────────────────────────────────────────────────────────────────────
-- notify_shift_delta() — POSTs the changed vendor row to the Edge Function
--
-- SECURITY DEFINER     — runs as owner so it can read vault.decrypted_secrets.
-- set search_path = '' — hijack-safe; every reference is schema-qualified.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.notify_shift_delta()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_project_url text;
    v_service_key text;
begin
    select decrypted_secret into v_project_url
        from vault.decrypted_secrets where name = 'project_url';
    select decrypted_secret into v_service_key
        from vault.decrypted_secrets where name = 'service_role_key';

    -- Degrade gracefully: never let a missing secret abort the shift write.
    if v_project_url is null or v_service_key is null then
        raise warning 'notify_shift_delta: missing Vault secret project_url/service_role_key — skipping push';
        return new;
    end if;

    perform net.http_post(
        url := v_project_url || '/functions/v1/shift-notify',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || v_service_key
        ),
        body := jsonb_build_object(
            'type', 'shift',
            'event_vendor_id', new.id,
            'event_id', new.event_id,
            'profile_id', new.profile_id,
            'pending_shift_delta', new.pending_shift_delta,
            'notification_threshold', new.notification_threshold
        )
    );

    return new;
end;
$$;

comment on function public.notify_shift_delta()
    is 'AFTER UPDATE trigger fn (SHIFT-643): POSTs a changed event_vendors row to '
       'the shift-notify Edge Function via pg_net. Reads project_url/service_role_key '
       'from Vault; no-ops with a warning if they are unset.';

-- ─────────────────────────────────────────────────────────────────────────────
-- Trigger: fire only on a genuine new shift delta for a claimed vendor.
--   AFTER UPDATE OF pending_shift_delta  → ignores ack-only writes (vendor ack
--       sets has_acknowledged_latest_shift, never this column) and INSERTs.
--   IS DISTINCT FROM old                 → a full-row vendor upsert that re-sends
--       the same value (name/role edit) does not re-notify.
--   profile_id IS NOT NULL               → only claimed collaborators have devices.
-- ─────────────────────────────────────────────────────────────────────────────
drop trigger if exists trg_notify_shift_delta on public.event_vendors;
create trigger trg_notify_shift_delta
    after update of pending_shift_delta on public.event_vendors
    for each row
    when (
        new.pending_shift_delta is not null
        and new.pending_shift_delta is distinct from old.pending_shift_delta
        and new.profile_id is not null
        and new.deleted_at is null
    )
    execute function public.notify_shift_delta();
