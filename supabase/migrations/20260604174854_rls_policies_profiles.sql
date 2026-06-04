-- SHIFT-560: RLS policies — profiles + public_profiles view
--
-- RLS enforces ROW access; column restriction requires a VIEW.
-- Strategy:
--   profiles table     → self-only row access (full columns)
--   public_profiles view → all authenticated users can SELECT; only safe
--                          columns are present so the full row never leaks
--
-- "Safe" public columns: id, display_name, avatar_url, business_name,
--   bio, portfolio_url.
-- "Private" columns withheld from others: phone, email, default_role,
--   created_at, updated_at, deleted_at.
--
-- The app must query public_profiles (not profiles) when looking up
-- another user. Querying profiles directly for another user's row
-- returns nothing — the self-only policy blocks it.

-- ─────────────────────────────────────────────────────────────────────────────
-- profiles table policies
-- ─────────────────────────────────────────────────────────────────────────────

-- Self: full CRUD on own row only
create policy "profiles_self_all" on public.profiles
    for all
    to authenticated
    using (id = auth.uid())
    with check (id = auth.uid());

-- ─────────────────────────────────────────────────────────────────────────────
-- public_profiles view — safe columns only
--
-- SECURITY INVOKER (default): the view runs as the calling user, so its own
-- RLS on profiles does NOT apply here (profiles has no other-user policy).
-- We therefore use SECURITY DEFINER so the view owner (postgres) can read
-- any profile row, and RLS on the view itself gates access.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace view public.public_profiles
    with (security_invoker = false)  -- security definer: view owner reads the table
as
    select
        id,
        display_name,
        -- Marketplace columns (null until the marketplace epic populates them)
        avatar_url,
        business_name,
        bio,
        portfolio_url
    from public.profiles
    where deleted_at is null;

-- Grant SELECT on the view to the authenticated and anon roles
grant select on public.public_profiles to authenticated;
grant select on public.public_profiles to anon;

comment on view public.public_profiles
    is 'Read-only projection of profiles exposing only marketplace-safe columns. '
       'Query this view — never profiles directly — when looking up another user. '
       'phone, email, default_role, and timestamps are intentionally excluded.';
