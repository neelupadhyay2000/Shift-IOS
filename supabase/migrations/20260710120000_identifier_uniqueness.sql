-- ─────────────────────────────────────────────────────────────────────────────
-- One person, one account: identifier-uniqueness check (soft model)
--
-- GOAL
--   Every account carries both an email and a phone, and no email or phone may
--   belong to two accounts — the way Facebook/Google/Instagram behave.
--
-- WHY AN RPC AND NOT A CLIENT LOOKUP
--   GoTrue's OTP is sign-in-OR-signup in a single call and deliberately gives an
--   anonymous client no "does this identifier exist?" answer (enumeration
--   protection). So there is no built-in pre-check to gate signup on. This RPC is
--   that pre-check. It reads `auth.users` (the verified identities) and
--   `public.profiles` (which also holds the *stored* second credential that is not
--   yet a GoTrue identity), so it catches a collision on either.
--
-- THE SOFT MODEL'S LIMIT (documented on purpose)
--   The second credential is stored in `profiles`, unverified, so it is not a
--   GoTrue sign-in identity. This RPC prevents a *silent* duplicate — a signup
--   whose identifier is already stored elsewhere is refused — but it cannot let
--   someone sign in by a credential that lives only in `profiles`. Such a user is
--   told to sign in with the account's other (verified) method. The strict model
--   (verify both) would remove this rough edge; the trade was low signup friction.
--
-- ENUMERATION
--   This RPC is, by design, an existence oracle callable by anon (it must run
--   before the user is authenticated, at the start of signup). That is the cost of
--   the soft model. It returns only booleans — never which account, never a name —
--   and PostgREST rate limits apply. If this becomes a problem, the mitigation is
--   to move it behind an Edge Function with a captcha/turnstile, or adopt the
--   strict model and delete it.
-- ─────────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
-- Normalization helpers — one definition, used by the RPC and the backstop index
-- so the client, the check, and the constraint can never disagree on what "same"
-- means. IMMUTABLE so they're index-usable.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.norm_email(p_email text)
returns text
language sql
immutable
set search_path = ''
as $$
    select nullif(lower(btrim(coalesce(p_email, ''))), '')
$$;

comment on function public.norm_email(text)
    is 'Canonical email form for identity comparison: trimmed, lowercased, blank → null.';

create or replace function public.norm_phone_digits(p_phone text)
returns text
language sql
immutable
set search_path = ''
as $$
    -- Digits only. GoTrue stores auth.users.phone without the leading '+', while
    -- profiles.phone and client input may carry '+' and formatting; comparing on
    -- digits makes all of them line up.
    select nullif(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), '')
$$;

comment on function public.norm_phone_digits(text)
    is 'Canonical phone form for identity comparison: digits only, blank → null.';

-- ─────────────────────────────────────────────────────────────────────────────
-- identifier_status(p_email, p_phone)
--
--   For each supplied identifier, reports whether it is already in use by ANY
--   account and, separately, whether that account is the CALLER's own (so the
--   Edit Account screen doesn't flag a user's own credential as taken). A null
--   argument is simply not checked and comes back false.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.identifier_status(
    p_email text default null,
    p_phone text default null
)
returns table (
    email_in_use  boolean,
    phone_in_use  boolean,
    email_is_mine boolean,
    phone_is_mine boolean
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
    -- Every place an identifier can live, unified to (kind, value, owner).
    owners as (
        select 'email'::text as kind,
               public.norm_email(u.email) as value,
               u.id as owner
          from auth.users u
         where u.email is not null
        union all
        select 'phone', public.norm_phone_digits(u.phone), u.id
          from auth.users u
         where u.phone is not null
        union all
        select 'email', public.norm_email(p.email), p.id
          from public.profiles p
         where p.deleted_at is null and p.email is not null
        union all
        select 'phone', public.norm_phone_digits(p.phone), p.id
          from public.profiles p
         where p.deleted_at is null and p.phone is not null
    )
    select
        (a.email is not null and exists (
            select 1 from owners o where o.kind = 'email' and o.value = a.email))                          as email_in_use,
        (a.phone is not null and exists (
            select 1 from owners o where o.kind = 'phone' and o.value = a.phone))                          as phone_in_use,
        (a.email is not null and a.uid is not null and exists (
            select 1 from owners o where o.kind = 'email' and o.value = a.email and o.owner = a.uid)
         and not exists (
            select 1 from owners o where o.kind = 'email' and o.value = a.email and o.owner <> a.uid))     as email_is_mine,
        (a.phone is not null and a.uid is not null and exists (
            select 1 from owners o where o.kind = 'phone' and o.value = a.phone and o.owner = a.uid)
         and not exists (
            select 1 from owners o where o.kind = 'phone' and o.value = a.phone and o.owner <> a.uid))     as phone_is_mine
      from args a;
$$;

comment on function public.identifier_status(text, text)
    is 'Signup/edit dedupe: reports whether an email and/or phone is already used '
       'by any account (auth.users or profiles), and whether it is the caller''s '
       'own. Returns booleans only — never the owning account. Callable by anon '
       'because it must run before authentication at signup.';

-- Runs pre-auth, so anon needs it; authenticated needs it for the Edit screen.
revoke all on function public.identifier_status(text, text) from public;
grant execute on function public.identifier_status(text, text) to anon, authenticated;

-- The DB-level backstop (partial unique indexes on the stored credentials) is a
-- SEPARATE migration (20260710130000), so that if prod already holds a duplicate
-- and the index creation aborts, this RPC — the piece the app actually depends on
-- — still lands.
