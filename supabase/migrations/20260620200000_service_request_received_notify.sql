-- Marketplace Requests (E11) — Story 3a: request_received push trigger
--
-- AFTER INSERT on service_requests → POST {type:'request_received'} to the
-- shift-notify Edge Function via pg_net, so the targeted vendor gets an alert
-- push ("New request for {event_title}"). Mirrors the Vault pattern from
-- 20260606130000_shift_notify_trigger.sql: SECURITY DEFINER reads
-- project_url/service_role_key from Vault and degrades gracefully (warn + no-op)
-- if they're unset, so creating a request never fails on this path.

create extension if not exists pg_net;

create or replace function public.notify_service_request_received()
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

    if v_project_url is null or v_service_key is null then
        raise warning 'notify_service_request_received: missing Vault secret — skipping push';
        return new;
    end if;

    perform net.http_post(
        url := v_project_url || '/functions/v1/shift-notify',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || v_service_key
        ),
        body := jsonb_build_object(
            'type', 'request_received',
            'request_id', new.id,
            'vendor_profile_id', new.vendor_profile_id,
            'event_title', new.event_title
        )
    );

    return new;
end;
$$;

comment on function public.notify_service_request_received()
    is 'AFTER INSERT trigger fn (E11): POSTs a new pending service_request to the '
       'shift-notify Edge Function (type request_received) so the vendor is pushed. '
       'Vault-backed; no-ops with a warning if secrets are unset.';

drop trigger if exists trg_notify_service_request_received on public.service_requests;
create trigger trg_notify_service_request_received
    after insert on public.service_requests
    for each row
    when (new.status = 'pending' and new.deleted_at is null)
    execute function public.notify_service_request_received();
