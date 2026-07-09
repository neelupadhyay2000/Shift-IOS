-- Marketplace Launch (E24 Task 3) — close the anon read hole on public_profiles.
--
-- WHY THIS MATTERS
-- `public_profiles` is a VIEW, and views carry no RLS of their own — the GRANT
-- *is* the access gate. It was created `security_invoker = false` (definer), so
-- the view owner reads `profiles` past RLS and returns whatever the caller is
-- granted. Because SELECT was granted to `anon`, anyone holding the app's
-- publicly-embedded anon key could enumerate every user's id, display_name,
-- avatar_url, business_name, bio and portfolio_url without ever signing in.
-- Verified against dev before this migration:
--     GET /rest/v1/public_profiles?select=*  (apikey: anon)  → 200 + real rows
--
-- WHAT STILL WORKS (verified before writing this)
--   * The app signs in before any marketplace read: `RootContainerView` gates on
--     `SignInView(isDismissible: false)`, and `MarketplaceService` (the only
--     caller of the view — fetchVendorProfile / fetchMyProfilePrefill) runs with
--     the user's JWT, i.e. the `authenticated` role, whose grant is untouched.
--   * Invite-link previews are unaffected: `shift://invite/{id}` is a device deep
--     link with no unauthenticated network fetch. The invite body carries only a
--     plain-text link plus an App Store URL, and the claim itself goes through
--     `claim_invite_by_id()`, already revoked from `anon`.
--   * The directory RPCs (`search_vendors`, `get_saved_vendors`,
--     `get_vendor_reviews`, …) are SECURITY DEFINER and join `public_profiles`
--     as the function owner, so they never consult the caller's grant.
--   * Auth (OTP request/verify) uses GoTrue endpoints, not PostgREST.
--
-- Defense in depth: `profiles` and `marketplace_waitlist` already return `[]` to
-- anon (RLS enabled, no anon policy), but the Data API's auto-grant on new public
-- tables left the table privilege in place. Revoke it so a future policy mistake
-- can't turn a grant into a leak. All writes to `profiles` are granted explicitly
-- to `authenticated` (see 20260612130000_profiles_comped_until.sql), so nothing
-- signup-related depends on the anon grant.

-- The actual leak: a view whose only gate is the grant.
revoke select on public.public_profiles from anon;

-- Belt and suspenders on the RLS-protected tables behind it.
revoke all on public.profiles from anon;
revoke all on public.marketplace_waitlist from anon;

-- `authenticated` retains SELECT on the view — explicitly re-asserted here so the
-- intent survives a future `create or replace view` (which resets privileges).
grant select on public.public_profiles to authenticated;

comment on view public.public_profiles
    is 'Read-only projection of profiles exposing only marketplace-safe columns. '
       'Query this view — never profiles directly — when looking up another user. '
       'phone, email, default_role, and timestamps are intentionally excluded. '
       'AUTHENTICATED-ONLY (E24 Task 3): anon SELECT was revoked — this view has no '
       'RLS of its own, so the grant is the gate. Never re-grant it to anon.';
