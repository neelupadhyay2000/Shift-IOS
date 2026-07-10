-- ─────────────────────────────────────────────────────────────────────────────
-- Backstop: the database is the final arbiter of identifier uniqueness.
--
-- The app checks `identifier_status` before writing a credential, but a race (two
-- signups claiming the same phone at once) or a client bug could still slip a
-- duplicate through. These partial unique indexes make a duplicate stored
-- credential simply impossible — the write fails with 23505 and the app surfaces
-- "already belongs to another account".
--
-- Kept out of 20260710120000 on purpose: if prod already contains a duplicate,
-- an index build here aborts, but the RPC that ships depends on has already
-- landed. If this migration fails, find the collision and resolve it:
--
--   select public.norm_email(email) as e, count(*)
--     from public.profiles where deleted_at is null
--    group by 1 having count(*) > 1;
--   select public.norm_phone_digits(phone) as p, count(*)
--     from public.profiles where deleted_at is null
--    group by 1 having count(*) > 1;
--
-- then re-run. At launch scale (a handful of accounts) no collision is expected.
-- ─────────────────────────────────────────────────────────────────────────────

create unique index if not exists profiles_email_unique_idx
    on public.profiles (public.norm_email(email))
    where deleted_at is null and public.norm_email(email) is not null;

create unique index if not exists profiles_phone_unique_idx
    on public.profiles (public.norm_phone_digits(phone))
    where deleted_at is null and public.norm_phone_digits(phone) is not null;
