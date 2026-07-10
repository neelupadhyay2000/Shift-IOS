-- ─────────────────────────────────────────────────────────────────────────────
-- Vendor contact info — reachable vendors after a marketplace booking
--
-- THE BUG
--   `respond_to_service_request` created the claimed `event_vendors` row with only
--   (event_id, profile_id, display_name, role, invited_at, accepted_at). But
--   `event_vendors.invited_phone` / `invited_email` are the two columns that map to
--   `VendorModel.phone` / `.email`, and VendorManagerView gates its Call button on
--   a non-empty phone. So a vendor booked through the marketplace landed in the
--   planner's event with no contact details and no way to be reached. The classic
--   invite flow only worked because the planner typed the contact in by hand.
--
-- WHY A SEPARATE TABLE, NOT COLUMNS ON vendor_profiles
--   `vendor_profiles_public_select` grants every authenticated user SELECT on the
--   whole row of any listed vendor, and the client reads that table directly.
--   Postgres RLS is row-level, not column-level, so contact columns there would be
--   readable by anyone browsing the directory. Contact must never be publicly
--   readable: it is disclosed to exactly one planner, at the moment the vendor
--   accepts their request, by being copied into that event.
--
-- WHY NOT REUSE profiles.email / profiles.phone
--   Those are auth credentials. Handing a planner someone's login identity is a
--   different consent than publishing a business contact, and vendors routinely
--   want a work line rather than a personal cell. They're also unreliable:
--   `profiles.phone` is null for email signups, and `profiles.email` is only filled
--   for phone signups once they clear CompleteProfileView.
--
-- REQUIRED TO LIST, NOT REQUIRED TO EXIST
--   Enforced by a trigger, because `is_listed` is flipped client-side (the
--   vendor_profiles_self_all policy permits a direct UPDATE), so a CHECK on
--   vendor_profiles could not see the other table and the client cannot be trusted
--   to self-enforce. An unlisted vendor may exist while they fill this in; a listed
--   one is always reachable.
-- ─────────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. The table
-- ─────────────────────────────────────────────────────────────────────────────
create table public.vendor_contacts (
    profile_id     uuid primary key references public.profiles(id) on delete cascade,

    -- Business contact, published to planners on acceptance. Deliberately distinct
    -- from profiles.email / profiles.phone (auth identity).
    contact_email  text not null
        constraint vendor_contacts_email_shape
        check (btrim(contact_email) <> '' and position('@' in contact_email) > 1),

    -- Free-form on input; digits are what matter. 7–15 digits is the E.164 range,
    -- matching PhoneAuthService.isValidE164 on the client.
    contact_phone  text not null
        constraint vendor_contacts_phone_shape
        check (length(regexp_replace(contact_phone, '\D', '', 'g')) between 7 and 15),

    created_at     timestamptz not null default now(),
    updated_at     timestamptz not null default now()
);

comment on table public.vendor_contacts
    is 'A vendor''s business contact details. NEVER publicly readable — no public '
       'select policy, revoked from anon. Disclosed to a single planner only when '
       'the vendor accepts their service request, at which point '
       'respond_to_service_request copies it into that event''s event_vendors row. '
       'Required before a vendor_profiles row may set is_listed (see the trigger '
       'below). Online-only: not in the SwiftData sync stack or realtime publication.';

comment on column public.vendor_contacts.contact_email
    is 'Business email shown to planners whose requests this vendor accepts.';
comment on column public.vendor_contacts.contact_phone
    is 'Business phone shown to planners whose requests this vendor accepts.';

create trigger set_updated_at
    before update on public.vendor_contacts
    for each row execute function public.set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. RLS — self only. No public select policy, by design.
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.vendor_contacts enable row level security;

create policy "vendor_contacts_self_all" on public.vendor_contacts
    for all
    to authenticated
    using (profile_id = auth.uid())
    with check (profile_id = auth.uid());

-- Authenticated-only: revoke the Data API's auto-grants to anon.
revoke all on public.vendor_contacts from anon;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Backfill from the auth identity where it happens to exist, then unlist any
--    vendor still missing contact details.
--
--    Unlisting is the safe failure mode: a listed vendor with no contact is the
--    exact bug this migration closes, and the trigger below would otherwise reject
--    their next profile edit with a confusing error. They re-list the moment they
--    fill the fields in.
-- ─────────────────────────────────────────────────────────────────────────────
insert into public.vendor_contacts (profile_id, contact_email, contact_phone)
select vp.profile_id, btrim(p.email), btrim(p.phone)
  from public.vendor_profiles vp
  join public.profiles p on p.id = vp.profile_id
 where vp.deleted_at is null
   and coalesce(btrim(p.email), '') <> ''
   and position('@' in p.email) > 1
   and length(regexp_replace(coalesce(p.phone, ''), '\D', '', 'g')) between 7 and 15
on conflict (profile_id) do nothing;

update public.vendor_profiles vp
   set is_listed = false
 where vp.is_listed
   and not exists (
        select 1 from public.vendor_contacts vc where vc.profile_id = vp.profile_id
   );

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. A listed vendor must be reachable.
--
--    BEFORE INSERT OR UPDATE on vendor_profiles: reject is_listed = true unless a
--    vendor_contacts row exists. SECURITY DEFINER so it reads vendor_contacts past
--    that table's self-only RLS (the trigger runs as the client's role otherwise
--    and would see nothing — which would pass the check for the owner and fail for
--    no one else, i.e. exactly backwards).
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.require_vendor_contact_to_list()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.is_listed and new.deleted_at is null then
        if not exists (
            select 1 from public.vendor_contacts vc
             where vc.profile_id = new.profile_id
        ) then
            raise exception
                'A business email and phone are required before listing in the marketplace.'
                using errcode = '23514';
        end if;
    end if;
    return new;
end;
$$;

comment on function public.require_vendor_contact_to_list()
    is 'Guards vendor_profiles.is_listed: no vendor appears in the directory '
       'without a vendor_contacts row, so a planner can always reach a vendor they '
       'book. Enforced server-side because is_listed is written directly by the '
       'client under vendor_profiles_self_all.';

create trigger vendor_profiles_require_contact_to_list
    before insert or update on public.vendor_profiles
    for each row execute function public.require_vendor_contact_to_list();

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. respond_to_service_request — copy the contact into the event on accept.
--
--    Writes into event_vendors.invited_email / invited_phone, which is what the
--    iOS VendorModel already reads. Safe to reuse those columns even though they
--    also feed invite-claim matching: both claim RPCs (20260605000000,
--    20260609000000) require `v.profile_id is null`, and this path sets profile_id
--    on the same row, so a contact-filled row can never become claimable by anyone
--    else.
--
--    Only fills a blank — never overwrites a contact the planner typed when they
--    invited this vendor by hand.
--
--    Body is otherwise identical to 20260620190000.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.respond_to_service_request(
    p_request_id uuid,
    p_accept     boolean,
    p_message    text default null
)
returns table (
    request_id            uuid,
    status                text,
    event_vendor_id       uuid,
    -- Name must match 20260620190000 exactly: renaming an OUT column is a return-
    -- type change (42P13), and the iOS client decodes this key.
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
    v_contact_email   text;
    v_contact_phone   text;
    v_block           jsonb;
    v_block_id        uuid;
    v_assigned        int := 0;
begin
    if v_uid is null then
        raise exception 'respond_to_service_request: not authenticated'
            using errcode = '28000';
    end if;

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
    select coalesce(nullif(btrim(p.business_name), ''), nullif(btrim(p.display_name), ''), '')
      into v_display_name
      from public.profiles p
     where p.id = v_uid;

    select coalesce(nullif(btrim(vp.category), ''), 'custom')
      into v_role
      from public.vendor_profiles vp
     where vp.profile_id = v_uid;
    v_role := coalesce(v_role, 'custom');   -- no vendor_profiles row → fallback

    -- The disclosure: this is the moment the vendor's business contact becomes
    -- visible to this one planner, in this one event.
    select vc.contact_email, vc.contact_phone
      into v_contact_email, v_contact_phone
      from public.vendor_contacts vc
     where vc.profile_id = v_uid;

    select id into v_event_vendor_id
      from public.event_vendors
     where event_id = v_req.event_id
       and profile_id = v_uid
       and deleted_at is null
     limit 1;

    if v_event_vendor_id is null then
        insert into public.event_vendors
            (event_id, profile_id, display_name, role, invited_at, accepted_at,
             invited_email, invited_phone)
        values
            (v_req.event_id, v_uid, coalesce(v_display_name, ''), v_role, now(), now(),
             v_contact_email, v_contact_phone)
        returning id into v_event_vendor_id;
    else
        update public.event_vendors
           set accepted_at   = coalesce(accepted_at, now()),
               display_name  = case when btrim(display_name) = '' then coalesce(v_display_name, '') else display_name end,
               role          = case when btrim(role) = '' then v_role else role end,
               -- Fill a blank; never clobber what the planner typed on invite.
               invited_email = case when coalesce(btrim(invited_email), '') = ''
                                    then v_contact_email else invited_email end,
               invited_phone = case when coalesce(btrim(invited_phone), '') = ''
                                    then v_contact_phone else invited_phone end
         where id = v_event_vendor_id;
    end if;

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
                set deleted_at = null;
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
       'claimed event_vendors row (idempotent per event+vendor), copies the vendor''s '
       'business contact from vendor_contacts into that row so the planner can reach '
       'them, and assigns the still-existing requested blocks — turning on '
       'can_access_event() so all existing collaboration activates. Gate: auth.uid() '
       'must be the request''s vendor_profile_id and status must be pending. '
       'SECURITY DEFINER.';
