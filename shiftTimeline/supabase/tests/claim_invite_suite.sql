-- SHIFT-628: claim_invite() test suite
--
-- Proves the acceptance criteria: the claim runs server-side and a client
-- cannot claim an invite that doesn't match its authenticated identity.
--
-- Harness (same as rls_suite.sql):
--   DO block runs as postgres (bypasses RLS) for setup/teardown.
--   set_config('request.jwt.claim.sub', uid, true) → fakes auth.uid().
--   SET LOCAL ROLE authenticated → activates RLS / the authenticated grant.
--   RESET ROLE → back to postgres.
--   ASSERT / RAISE → any failure aborts with a clear message.
--
-- Run against dev:
--   supabase db query \
--     --db-url "postgresql://postgres:<pw>@db.<ref>.supabase.co:5432/postgres" \
--     "$(cat supabase/tests/claim_invite_suite.sql)"
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_owner_id     uuid := '00000001-0000-0000-0000-0000000000c8';
    v_claimant_id  uuid := '00000002-0000-0000-0000-0000000000c8';
    v_attacker_id  uuid := '00000003-0000-0000-0000-0000000000c8';
    v_event_id     uuid := '00000010-0000-0000-0000-0000000000c8';

    v_ev_email     uuid := '00000021-0000-0000-0000-0000000000c8'; -- matches claimant by email
    v_ev_phone     uuid := '00000022-0000-0000-0000-0000000000c8'; -- matches claimant by phone
    v_ev_other     uuid := '00000023-0000-0000-0000-0000000000c8'; -- addressed to a third party
    v_ev_contact   uuid := '00000024-0000-0000-0000-0000000000c8'; -- claimant contact but never invited
    v_ev_already   uuid := '00000025-0000-0000-0000-0000000000c8'; -- already claimed by another profile

    v_count        bigint;
    v_profile      uuid;
    v_accepted     timestamptz;
BEGIN

    -- =========================================================================
    -- SETUP (postgres superuser)
    -- =========================================================================

    -- Verified identities. Supabase stores auth.users.phone as E.164 digits
    -- without a leading "+", e.g. 15551230001.
    INSERT INTO auth.users (id, email, phone, aud, role, email_confirmed_at, created_at, updated_at)
    VALUES
        (v_owner_id,    'claim_owner@test.shift', NULL,          'authenticated', 'authenticated', now(), now(), now()),
        (v_claimant_id, 'claimant@test.shift',    '15551230001', 'authenticated', 'authenticated', now(), now(), now()),
        (v_attacker_id, 'attacker@test.shift',    '15559990002', 'authenticated', 'authenticated', now(), now(), now());

    -- The attacker's PROFILE is deliberately spoofed to the claimant's contact.
    -- claim_invite must ignore it (it reads auth.users), so the spoof is useless.
    INSERT INTO public.profiles (id, display_name, email, phone) VALUES
        (v_owner_id,    'Owner',    'claim_owner@test.shift', NULL),
        (v_claimant_id, 'Claimant', 'claimant@test.shift',    '15551230001'),
        (v_attacker_id, 'Attacker', 'claimant@test.shift',    '15551230001');

    INSERT INTO public.events (id, owner_id, title, date)
    VALUES (v_event_id, v_owner_id, 'Claim Test Event', now());

    INSERT INTO public.event_vendors
        (id, event_id, profile_id, invited_email, invited_phone, display_name, role, notification_threshold, invited_at, accepted_at)
    VALUES
        -- matches claimant by email (mixed case → tests case-insensitivity)
        (v_ev_email,   v_event_id, NULL,        'Claimant@Test.Shift',     NULL,             'By Email', 'photographer', 300, now(), NULL),
        -- matches claimant by phone (planner typed a formatted local number)
        (v_ev_phone,   v_event_id, NULL,        NULL,                      '(555) 123-0001', 'By Phone', 'dj',           300, now(), NULL),
        -- addressed to a third party
        (v_ev_other,   v_event_id, NULL,        'someone.else@test.shift', NULL,             'Other',    'florist',      300, now(), NULL),
        -- claimant's contact but NEVER invited (invited_at NULL) → must be ignored
        (v_ev_contact, v_event_id, NULL,        'claimant@test.shift',     NULL,             'Contact',  'custom',       300, NULL,  NULL),
        -- already claimed by another profile → must not be hijacked
        (v_ev_already, v_event_id, v_owner_id,  'claimant@test.shift',     NULL,             'Already',  'caterer',      300, now(), now());

    RAISE NOTICE '── Setup complete ──────────────────────────────────────────';

    -- =========================================================================
    -- SECURITY: the attacker cannot claim invites addressed to the claimant,
    -- even though the attacker's profile was rewritten to match — because the
    -- claim reads the verified auth.users identity, not public.profiles.
    -- =========================================================================
    PERFORM set_config('request.jwt.claim.sub', v_attacker_id::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';

    SELECT count(*) INTO v_count FROM public.claim_invite();
    ASSERT v_count = 0, format('FAIL security: attacker claimed %s rows, expected 0', v_count);
    RAISE NOTICE 'PASS security: attacker (profile spoofed to victim) claimed 0 rows';

    EXECUTE 'RESET ROLE';

    -- The claimant's invites must remain unclaimed after the attack.
    SELECT profile_id INTO v_profile FROM public.event_vendors WHERE id = v_ev_email;
    ASSERT v_profile IS NULL, 'FAIL security: email invite was claimed by the attacker';
    SELECT profile_id INTO v_profile FROM public.event_vendors WHERE id = v_ev_phone;
    ASSERT v_profile IS NULL, 'FAIL security: phone invite was claimed by the attacker';
    RAISE NOTICE 'PASS security: claimant invites remain unclaimed after attacker attempt';

    -- =========================================================================
    -- CLAIMANT: claims exactly the two invites addressed to their identity.
    -- =========================================================================
    PERFORM set_config('request.jwt.claim.sub', v_claimant_id::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';

    SELECT count(*) INTO v_count FROM public.claim_invite();
    ASSERT v_count = 2, format('FAIL claimant: claimed %s rows, expected 2 (email + phone)', v_count);
    RAISE NOTICE 'PASS claimant: claimed 2 invites (email + phone)';

    -- Idempotent: a second claim finds nothing left.
    SELECT count(*) INTO v_count FROM public.claim_invite();
    ASSERT v_count = 0, format('FAIL idempotency: second claim returned %s rows, expected 0', v_count);
    RAISE NOTICE 'PASS idempotency: re-claim returns 0 rows';

    EXECUTE 'RESET ROLE';

    -- Linkage: matched rows now point to the claimant with an accept time.
    SELECT profile_id, accepted_at INTO v_profile, v_accepted FROM public.event_vendors WHERE id = v_ev_email;
    ASSERT v_profile = v_claimant_id, 'FAIL: email invite not linked to claimant';
    ASSERT v_accepted IS NOT NULL,    'FAIL: email invite accepted_at not set';
    RAISE NOTICE 'PASS: email invite linked to claimant with accepted_at set';

    SELECT profile_id INTO v_profile FROM public.event_vendors WHERE id = v_ev_phone;
    ASSERT v_profile = v_claimant_id, 'FAIL: phone invite not linked to claimant';
    RAISE NOTICE 'PASS: phone invite linked to claimant';

    -- Negatives: rows the claimant must NOT have touched.
    SELECT profile_id INTO v_profile FROM public.event_vendors WHERE id = v_ev_other;
    ASSERT v_profile IS NULL, 'FAIL: invite addressed to a third party was claimed';
    RAISE NOTICE 'PASS: third-party invite left unclaimed';

    SELECT profile_id INTO v_profile FROM public.event_vendors WHERE id = v_ev_contact;
    ASSERT v_profile IS NULL, 'FAIL: never-invited (invited_at NULL) row was claimed';
    RAISE NOTICE 'PASS: contact-only (never invited) row left unclaimed';

    SELECT profile_id INTO v_profile FROM public.event_vendors WHERE id = v_ev_already;
    ASSERT v_profile = v_owner_id, 'FAIL: already-claimed row was hijacked';
    RAISE NOTICE 'PASS: already-claimed row not hijacked';

    -- =========================================================================
    -- CLEANUP (deleting auth.users cascades to profiles → events → vendors)
    -- =========================================================================
    DELETE FROM auth.users WHERE id IN (v_owner_id, v_claimant_id, v_attacker_id);

    RAISE NOTICE '';
    RAISE NOTICE '═══════════════════════════════════════════════════════════════════════';
    RAISE NOTICE '  ALL claim_invite TESTS PASSED  ✓  (SHIFT-628)';
    RAISE NOTICE '═══════════════════════════════════════════════════════════════════════';

EXCEPTION WHEN OTHERS THEN
    EXECUTE 'RESET ROLE';
    DELETE FROM auth.users WHERE id IN (v_owner_id, v_claimant_id, v_attacker_id);
    RAISE;
END;
$$;
