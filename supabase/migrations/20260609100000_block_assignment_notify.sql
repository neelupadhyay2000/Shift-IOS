-- Vendor assignment notification: trigger that invokes the notify Edge Function
-- when a vendor is assigned to a block (block_vendors INSERT).
--
-- Mirrors the shift-notify trigger (SHIFT-643): a SECURITY DEFINER function reads
-- the project URL + service key from Vault and POSTs the assignment to the same
-- `shift-notify` Edge Function (which now branches on `type`). The function
-- resolves the assigned vendor's profile_id (only claimed collaborators have
-- devices) and the block title here, so the Edge Function only needs to fan out
-- to device_tokens.
--
-- Fires only on a genuine INSERT: an idempotent re-send of an existing assignment
-- arrives as INSERT ... ON CONFLICT DO UPDATE, which fires UPDATE (not INSERT)
-- triggers — so a re-sync never re-notifies.

create or replace function public.notify_block_assignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_project_url text;
    v_service_key text;
    v_profile_id  uuid;
    v_block_title text;
begin
    -- Only claimed collaborators have device tokens; skip contact-only vendors.
    select profile_id into v_profile_id
        from public.event_vendors where id = new.event_vendor_id;
    if v_profile_id is null then
        return new;
    end if;

    select title into v_block_title from public.blocks where id = new.block_id;

    select decrypted_secret into v_project_url
        from vault.decrypted_secrets where name = 'project_url';
    select decrypted_secret into v_service_key
        from vault.decrypted_secrets where name = 'service_role_key';

    -- Degrade gracefully: never let a missing secret abort the assignment write.
    if v_project_url is null or v_service_key is null then
        raise warning 'notify_block_assignment: missing Vault secret project_url/service_role_key — skipping push';
        return new;
    end if;

    perform net.http_post(
        url := v_project_url || '/functions/v1/shift-notify',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || v_service_key
        ),
        body := jsonb_build_object(
            'type', 'assignment',
            'event_vendor_id', new.event_vendor_id,
            'event_id', new.event_id,
            'profile_id', v_profile_id,
            'block_title', coalesce(v_block_title, 'a block')
        )
    );

    return new;
end;
$$;

comment on function public.notify_block_assignment()
    is 'AFTER INSERT trigger fn on block_vendors: POSTs an {type:assignment} payload '
       'to the shift-notify Edge Function via pg_net so the assigned (claimed) '
       'vendor gets an APNs alert. Reads project_url/service_role_key from Vault; '
       'no-ops with a warning if unset, or if the vendor is unclaimed (no devices).';

drop trigger if exists trg_notify_block_assignment on public.block_vendors;
create trigger trg_notify_block_assignment
    after insert on public.block_vendors
    for each row
    when (new.deleted_at is null)
    execute function public.notify_block_assignment();
