-- Marketplace Requests (E11) — Story 2: respond_to_service_request RPC
--
-- THE BRIDGE. When a vendor accepts a service request this single SECURITY DEFINER
-- function atomically claims a collaboration seat: it upserts a claimed
-- event_vendors row for (event, vendor) and assigns the requested blocks. That
-- claimed row makes can_access_event() true for the vendor, so EVERY existing
-- collaboration feature — read-only timeline RLS, realtime channels, hydration,
-- shift acks, go-live pushes — activates with zero further changes.
--
-- Modeled on claim_invite() (20260605000000): SECURITY DEFINER + search_path=''.
-- The caller cannot SELECT the event pre-accept (no RLS path), so the claim must
-- run server-side; the auth.uid() = vendor_profile_id assertion is the gate.
--
-- Returns one row: (request_id, status, event_vendor_id, assigned_blocks_count).

create or replace function public.respond_to_service_request(
    p_request_id uuid,
    p_accept     boolean,
    p_message    text default null
)
returns table (
    request_id            uuid,
    status                text,
    event_vendor_id       uuid,
    assigned_blocks_count int
)
language plpgsql
security definer
set search_path = ''
as $$
-- The RETURNS TABLE columns (e.g. event_vendor_id) share names with table columns
-- used in SQL below (block_vendors.event_vendor_id in ON CONFLICT). We never
-- reference the OUT columns by bare name — they're only returned positionally —
-- so resolve any ambiguity to the column.
#variable_conflict use_column
declare
    v_uid             uuid := auth.uid();
    v_req             public.service_requests;
    v_event_vendor_id uuid;
    v_display_name    text;
    v_role            text;
    v_block           jsonb;
    v_block_id        uuid;
    v_assigned        int := 0;
begin
    if v_uid is null then
        raise exception 'respond_to_service_request: not authenticated'
            using errcode = '28000';
    end if;

    -- Lock the request so concurrent responses can't race.
    select * into v_req
      from public.service_requests
     where id = p_request_id
       and deleted_at is null
     for update;

    if not found then
        raise exception 'respond_to_service_request: request % not found', p_request_id
            using errcode = 'P0002';
    end if;
    if v_req.vendor_profile_id <> v_uid then
        raise exception 'respond_to_service_request: caller is not the addressed vendor'
            using errcode = '42501';
    end if;
    if v_req.status <> 'pending' then
        raise exception 'respond_to_service_request: request is not pending (status=%)', v_req.status
            using errcode = 'P0001';
    end if;

    -- ── Decline ───────────────────────────────────────────────────────────────
    if not coalesce(p_accept, false) then
        update public.service_requests
           set status = 'declined',
               response_message = p_message,
               responded_at = now()
         where id = p_request_id;
        return query select p_request_id, 'declined'::text, null::uuid, 0;
        return;
    end if;

    -- ── Accept ────────────────────────────────────────────────────────────────
    -- Display name + role for the claimed collaboration row.
    select coalesce(nullif(btrim(p.business_name), ''), nullif(btrim(p.display_name), ''), '')
      into v_display_name
      from public.profiles p
     where p.id = v_uid;

    select coalesce(nullif(btrim(vp.category), ''), 'custom')
      into v_role
      from public.vendor_profiles vp
     where vp.profile_id = v_uid;
    v_role := coalesce(v_role, 'custom');   -- no vendor_profiles row → fallback

    -- Idempotent: reuse a non-deleted event_vendors row for (event, vendor) if one
    -- already exists (e.g. claimed via a prior invite); else create it.
    select id into v_event_vendor_id
      from public.event_vendors
     where event_id = v_req.event_id
       and profile_id = v_uid
       and deleted_at is null
     limit 1;

    if v_event_vendor_id is null then
        insert into public.event_vendors
            (event_id, profile_id, display_name, role, invited_at, accepted_at)
        values
            (v_req.event_id, v_uid, coalesce(v_display_name, ''), v_role, now(), now())
        returning id into v_event_vendor_id;
    else
        update public.event_vendors
           set accepted_at  = coalesce(accepted_at, now()),
               display_name = case when btrim(display_name) = '' then coalesce(v_display_name, '') else display_name end,
               role         = case when btrim(role) = '' then v_role else role end
         where id = v_event_vendor_id;
    end if;

    -- Assign requested blocks that still exist, aren't deleted, and belong to the
    -- event. The snapshot is validated against live blocks; deleted/foreign blocks
    -- are silently skipped. Idempotent per (block, event_vendor).
    for v_block in
        select value from jsonb_array_elements(coalesce(v_req.requested_blocks, '[]'::jsonb))
    loop
        v_block_id := nullif(v_block->>'block_id', '')::uuid;
        if v_block_id is null then
            continue;
        end if;
        if exists (
            select 1 from public.blocks b
            where b.id = v_block_id
              and b.event_id = v_req.event_id
              and b.deleted_at is null
        ) then
            insert into public.block_vendors (block_id, event_vendor_id, event_id)
            values (v_block_id, v_event_vendor_id, v_req.event_id)
            on conflict (block_id, event_vendor_id) do update
                set deleted_at = null;   -- resurrect a previously-removed assignment
            v_assigned := v_assigned + 1;
        end if;
    end loop;

    update public.service_requests
       set status = 'accepted',
           event_vendor_id = v_event_vendor_id,
           responded_at = now(),
           response_message = p_message
     where id = p_request_id;

    return query select p_request_id, 'accepted'::text, v_event_vendor_id, v_assigned;
end;
$$;

comment on function public.respond_to_service_request(uuid, boolean, text)
    is 'Vendor accept/decline of a service request. On accept, atomically upserts a '
       'claimed event_vendors row (idempotent per event+vendor) and assigns the '
       'still-existing requested blocks — turning on can_access_event() so all '
       'existing collaboration activates. Gate: auth.uid() must be the request''s '
       'vendor_profile_id and status must be pending. SECURITY DEFINER.';

revoke all on function public.respond_to_service_request(uuid, boolean, text) from public;
revoke all on function public.respond_to_service_request(uuid, boolean, text) from anon;
grant execute on function public.respond_to_service_request(uuid, boolean, text) to authenticated;
