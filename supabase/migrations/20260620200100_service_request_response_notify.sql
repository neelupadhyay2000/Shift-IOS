-- Marketplace Requests (E11) — Story 3b: request_response push trigger
--
-- AFTER UPDATE OF status on service_requests, when status flips to accepted or
-- declined (IS DISTINCT FROM old), → POST {type:'request_response'} to the
-- shift-notify Edge Function so the requesting planner gets an alert push
-- ("{business_name} accepted/declined your request"). The Edge Function resolves
-- the responder's business_name. Same Vault pattern + graceful degrade as 3a.
--
-- Fires for the RPC's UPDATE (respond_to_service_request) and the planner's own
-- cancel is excluded (cancel isn't accepted/declined).

create extension if not exists pg_net;

create or replace function public.notify_service_request_response()
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
        raise warning 'notify_service_request_response: missing Vault secret — skipping push';
        return new;
    end if;

    perform net.http_post(
        url := v_project_url || '/functions/v1/shift-notify',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || v_service_key
        ),
        body := jsonb_build_object(
            'type', 'request_response',
            'request_id', new.id,
            'planner_id', new.planner_id,
            'vendor_profile_id', new.vendor_profile_id,
            'status', new.status
        )
    );

    return new;
end;
$$;

comment on function public.notify_service_request_response()
    is 'AFTER UPDATE OF status trigger fn (E11): POSTs an accepted/declined '
       'service_request to the shift-notify Edge Function (type request_response) '
       'so the planner is pushed. Vault-backed; no-ops with a warning if secrets '
       'are unset.';

drop trigger if exists trg_notify_service_request_response on public.service_requests;
create trigger trg_notify_service_request_response
    after update of status on public.service_requests
    for each row
    when (
        new.status in ('accepted', 'declined')
        and new.status is distinct from old.status
        and new.deleted_at is null
    )
    execute function public.notify_service_request_response();
