-- Marketplace Request Chat (E12) — Story 2: request_message push trigger
--
-- AFTER INSERT on request_messages → resolve the OTHER participant (planner vs
-- vendor) from the parent service_request and POST {type:'request_message'} to
-- the shift-notify Edge Function so they get an alert push (sender name +
-- truncated body, deep-linking via com.shift.requestID). Same Vault pattern +
-- graceful degrade as the other notify triggers.
--
-- FUTURE WORK: push coalescing for chatty threads is deliberately out of v1 —
-- every message fires one push. A later iteration can debounce per recipient.

create extension if not exists pg_net;

create or replace function public.notify_request_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_project_url text;
    v_service_key text;
    v_recipient   uuid;
begin
    select decrypted_secret into v_project_url
        from vault.decrypted_secrets where name = 'project_url';
    select decrypted_secret into v_service_key
        from vault.decrypted_secrets where name = 'service_role_key';

    if v_project_url is null or v_service_key is null then
        raise warning 'notify_request_message: missing Vault secret — skipping push';
        return new;
    end if;

    -- The recipient is whichever participant isn't the sender.
    select case
               when r.planner_id = new.sender_id then r.vendor_profile_id
               else r.planner_id
           end
      into v_recipient
      from public.service_requests r
     where r.id = new.request_id
       and r.deleted_at is null;

    -- No resolvable counterpart (deleted request / non-participant) → no push.
    if v_recipient is null or v_recipient = new.sender_id then
        return new;
    end if;

    perform net.http_post(
        url := v_project_url || '/functions/v1/shift-notify',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || v_service_key
        ),
        body := jsonb_build_object(
            'type', 'request_message',
            'request_id', new.request_id,
            'recipient_id', v_recipient,
            'sender_id', new.sender_id,
            'body', new.body
        )
    );

    return new;
end;
$$;

comment on function public.notify_request_message()
    is 'AFTER INSERT trigger fn (E12): resolves the other request participant and '
       'POSTs the message to shift-notify (type request_message) for an alert push. '
       'Vault-backed; no-ops with a warning if secrets are unset.';

drop trigger if exists trg_notify_request_message on public.request_messages;
create trigger trg_notify_request_message
    after insert on public.request_messages
    for each row
    when (new.deleted_at is null)
    execute function public.notify_request_message();
