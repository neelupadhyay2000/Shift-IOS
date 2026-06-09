-- Go-live notification: trigger that invokes the notify Edge Function when an
-- event transitions to 'live', so every claimed vendor is pushed instantly.
--
-- Mirrors the shift / assignment triggers: a SECURITY DEFINER function reads the
-- project URL + service key from Vault and POSTs a {type:golive} payload to the
-- shift-notify Edge Function, which fans out an alert push to every claimed
-- vendor on the event (it resolves the recipients itself, so the trigger stays a
-- single HTTP call).
--
-- Fires only on a genuine transition INTO 'live' (status changed), so a full-row
-- event upsert that re-sends the same status does not re-notify.

create or replace function public.notify_event_live()
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

    -- Degrade gracefully: never let a missing secret abort the go-live write.
    if v_project_url is null or v_service_key is null then
        raise warning 'notify_event_live: missing Vault secret project_url/service_role_key — skipping push';
        return new;
    end if;

    perform net.http_post(
        url := v_project_url || '/functions/v1/shift-notify',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || v_service_key
        ),
        body := jsonb_build_object(
            'type', 'golive',
            'event_id', new.id,
            'event_title', coalesce(nullif(new.title, ''), 'Your event')
        )
    );

    return new;
end;
$$;

comment on function public.notify_event_live()
    is 'AFTER UPDATE OF status trigger fn on events: when an event goes live, POSTs '
       'a {type:golive} payload to the shift-notify Edge Function via pg_net so every '
       'claimed vendor gets an APNs alert. Reads project_url/service_role_key from Vault.';

drop trigger if exists trg_notify_event_live on public.events;
create trigger trg_notify_event_live
    after update of status on public.events
    for each row
    when (new.status = 'live' and new.status is distinct from old.status)
    execute function public.notify_event_live();
