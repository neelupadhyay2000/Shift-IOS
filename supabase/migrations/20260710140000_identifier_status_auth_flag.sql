-- ─────────────────────────────────────────────────────────────────────────────
-- identifier_status: add the "is this a verified login?" distinction.
--
-- WHY
--   The signup entry screen must tell three cases apart for an entered identifier:
--     • a verified GoTrue login (in auth.users)  → allow OTP; the person signs in
--     • a free identifier                         → allow OTP; new signup
--     • used ONLY as a stored second credential   → BLOCK; it belongs to an account
--       on another account's profiles row           whose login is the OTHER channel
--   The first version returned only `*_in_use`, which conflated the first and third
--   cases — it would have blocked a legitimate returning user from signing in.
--   Adding `*_is_auth` (present in auth.users) lets the client separate them:
--       block  ⟺  in_use AND NOT is_auth
--
--   DROP first: adding OUT columns changes the RETURNS TABLE shape, which
--   `create or replace` cannot do. Supersedes 20260710120000 (dev-only; prod sees
--   only this final form).
-- ─────────────────────────────────────────────────────────────────────────────

drop function if exists public.identifier_status(text, text);

create function public.identifier_status(
    p_email text default null,
    p_phone text default null
)
returns table (
    email_in_use  boolean,
    phone_in_use  boolean,
    email_is_mine boolean,
    phone_is_mine boolean,
    -- Present as a VERIFIED GoTrue identity (auth.users) — i.e. a real login for
    -- this identifier, not merely a value stored on a profiles row.
    email_is_auth boolean,
    phone_is_auth boolean
)
language sql
stable
security definer
set search_path = ''
as $$
    with args as (
        select public.norm_email(p_email)        as email,
               public.norm_phone_digits(p_phone)  as phone,
               auth.uid()                         as uid
    ),
    owners as (
        select 'email'::text as kind,
               public.norm_email(u.email) as value,
               u.id as owner,
               true  as is_auth
          from auth.users u
         where u.email is not null
        union all
        select 'phone', public.norm_phone_digits(u.phone), u.id, true
          from auth.users u
         where u.phone is not null
        union all
        select 'email', public.norm_email(p.email), p.id, false
          from public.profiles p
         where p.deleted_at is null and p.email is not null
        union all
        select 'phone', public.norm_phone_digits(p.phone), p.id, false
          from public.profiles p
         where p.deleted_at is null and p.phone is not null
    )
    select
        (a.email is not null and exists (
            select 1 from owners o where o.kind = 'email' and o.value = a.email))                       as email_in_use,
        (a.phone is not null and exists (
            select 1 from owners o where o.kind = 'phone' and o.value = a.phone))                       as phone_in_use,
        (a.email is not null and a.uid is not null
         and exists (select 1 from owners o where o.kind = 'email' and o.value = a.email and o.owner = a.uid)
         and not exists (select 1 from owners o where o.kind = 'email' and o.value = a.email and o.owner <> a.uid)) as email_is_mine,
        (a.phone is not null and a.uid is not null
         and exists (select 1 from owners o where o.kind = 'phone' and o.value = a.phone and o.owner = a.uid)
         and not exists (select 1 from owners o where o.kind = 'phone' and o.value = a.phone and o.owner <> a.uid)) as phone_is_mine,
        (a.email is not null and exists (
            select 1 from owners o where o.kind = 'email' and o.value = a.email and o.is_auth))         as email_is_auth,
        (a.phone is not null and exists (
            select 1 from owners o where o.kind = 'phone' and o.value = a.phone and o.is_auth))         as phone_is_auth
      from args a;
$$;

comment on function public.identifier_status(text, text)
    is 'Signup/edit dedupe. Per identifier: in_use (any account), is_mine (the '
       'caller''s), is_auth (a verified GoTrue login vs a stored-only second '
       'credential). Booleans only — never the owning account. Anon-callable '
       'because it runs before authentication at signup.';

revoke all on function public.identifier_status(text, text) from public;
grant execute on function public.identifier_status(text, text) to anon, authenticated;
