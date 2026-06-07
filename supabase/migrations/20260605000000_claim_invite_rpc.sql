-- SHIFT-628: claim_invite() — authoritative, secure claim-on-sign-in
--
-- Claiming an invite must be authoritative and secure: a client must NOT be able
-- to claim an invite whose phone/email doesn't match its *authenticated*
-- identity. We therefore run the match server-side in a SECURITY DEFINER
-- function that reads the caller's verified contact from auth.users (never the
-- client-writable public.profiles, which a malicious user could rewrite to
-- impersonate the invitee), and links only the rows that match.
--
-- Why server-side at all: under RLS a not-yet-claimed event_vendors row has
-- profile_id = null, so the invitee cannot even SELECT it (vendor_select requires
-- profile_id = auth.uid()). The claim therefore can't happen client-side; this
-- function matches across rows the caller cannot yet read, while the WHERE clause
-- restricts the write to invites addressed to the caller's own identity.
--
-- The matching mirrors the client-side VendorInviteClaim rule (SHIFT-627):
--   email — trimmed, case-insensitive equality
--   phone — equality after canonicalizing both sides to digits (US-default: a
--           bare 10-digit number gets a leading 1), matching the iOS
--           PhoneAuthService.normalizePhone used at sign-in.

-- ─────────────────────────────────────────────────────────────────────────────
-- Phone canonicalization helper — digits only, US-default country code.
-- search_path = '' for safety; pg_catalog built-ins (regexp_replace, length)
-- remain resolvable as they are always implicitly first on the path.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.normalize_phone_digits(raw text)
returns text
language sql
immutable
set search_path = ''
as $$
    with cleaned as (
        select regexp_replace(coalesce(raw, ''), '[^0-9]', '', 'g') as digits
    )
    select case
        when raw is null then null
        when length(digits) = 10 then '1' || digits
        else digits
    end
    from cleaned;
$$;

comment on function public.normalize_phone_digits(text)
    is 'Canonicalizes a phone string to digits only, prepending a US country code '
       'to bare 10-digit numbers. Mirrors iOS PhoneAuthService.normalizePhone so '
       'client and server agree on phone-invite matching.';

-- ─────────────────────────────────────────────────────────────────────────────
-- claim_invite() — links the caller to every invite addressed to their identity.
--
-- A row is claimable only when it is genuinely invited (invited_at set), still
-- unclaimed (profile_id null), not soft-deleted, and matches the caller's
-- verified auth.users contact. Returns the rows it claimed.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.claim_invite()
returns setof public.event_vendors
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_uid   uuid := auth.uid();
    v_email text;
    v_phone text;
begin
    if v_uid is null then
        raise exception 'claim_invite: not authenticated'
            using errcode = '28000';
    end if;

    -- Verified identity — read from auth.users, NEVER from public.profiles.
    select u.email, u.phone
      into v_email, v_phone
      from auth.users u
     where u.id = v_uid;

    return query
    update public.event_vendors v
       set profile_id  = v_uid,
           accepted_at = now()
     where v.profile_id is null
       and v.invited_at is not null
       and v.deleted_at is null
       and (
            -- Email match: trimmed, case-insensitive
            (
                v.invited_email is not null
                and v_email is not null
                and lower(btrim(v.invited_email)) = lower(btrim(v_email))
            )
            or
            -- Phone match: canonical digits, both sides non-trivial
            (
                v.invited_phone is not null
                and v_phone is not null
                and length(public.normalize_phone_digits(v.invited_phone)) >= 7
                and public.normalize_phone_digits(v.invited_phone)
                    = public.normalize_phone_digits(v_phone)
            )
       )
    returning v.*;
end;
$$;

comment on function public.claim_invite()
    is 'SHIFT-628: authoritative claim-on-sign-in. Links auth.uid() to every '
       'unclaimed, invited event_vendors row whose invited_phone/invited_email '
       'matches the caller''s VERIFIED auth.users identity (not the client-'
       'writable profiles row), setting profile_id + accepted_at. SECURITY '
       'DEFINER so it can match across rows the caller cannot yet read; the WHERE '
       'clause restricts the write to the caller''s own identity. Returns claimed rows.';

-- Only authenticated users may claim — never anon / public.
revoke all on function public.claim_invite() from public;
revoke all on function public.claim_invite() from anon;
grant execute on function public.claim_invite() to authenticated;
