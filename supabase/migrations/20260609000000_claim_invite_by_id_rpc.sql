-- Link-based (possession) invite claim: claim_invite_by_id()
--
-- Companion to claim_invite() (which matches the caller's VERIFIED phone/email).
-- This claims ONE specific event_vendors row by id — proof of possession of the
-- invite link (`shift://invite/{vendorID}`), which is delivered to the invitee's
-- phone/email. It makes invites work regardless of HOW the vendor signs in, so a
-- vendor invited by phone number can join via email OTP without phone OTP at all,
-- and Apple "Hide My Email" no longer blocks the match.
--
-- Security model: SECURITY DEFINER so it can claim a row the caller cannot yet
-- SELECT (the vendor_select policy requires profile_id = auth.uid(), which is
-- null pre-claim). The WHERE clause restricts the write to a single, still-
-- unclaimed, genuinely-invited, non-deleted row, and it's one-time: once
-- profile_id is set the row is no longer claimable, so a leaked/forwarded link
-- can't re-claim an already-accepted invite. Read-only vendor access keeps the
-- blast radius small. auth.uid() is required (authenticated only).

create or replace function public.claim_invite_by_id(p_vendor_id uuid)
returns setof public.event_vendors
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_uid uuid := auth.uid();
begin
    if v_uid is null then
        raise exception 'claim_invite_by_id: not authenticated'
            using errcode = '28000';
    end if;

    return query
    update public.event_vendors v
       set profile_id  = v_uid,
           accepted_at = now()
     where v.id = p_vendor_id
       and v.profile_id is null
       and v.invited_at is not null
       and v.deleted_at is null
    returning v.*;
end;
$$;

comment on function public.claim_invite_by_id(uuid)
    is 'Link-based (possession) invite claim: links auth.uid() to the single '
       'unclaimed, invited event_vendors row identified by p_vendor_id (the id '
       'carried in the shift://invite/{vendorID} link). SECURITY DEFINER so it '
       'can claim a row the caller cannot yet read; one-time (profile_id null). '
       'Companion to the identity-matching claim_invite().';

-- Only authenticated users may claim — never anon / public.
revoke all on function public.claim_invite_by_id(uuid) from public;
revoke all on function public.claim_invite_by_id(uuid) from anon;
grant execute on function public.claim_invite_by_id(uuid) to authenticated;
