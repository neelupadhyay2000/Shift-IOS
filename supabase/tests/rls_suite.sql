-- SHIFT-561: Automated RLS test suite
--
-- Tests three personas against every policy:
--   stranger  — authenticated user with no relationship to the event
--   vendor    — authenticated user in event_vendors (accepted collaborator)
--   owner     — authenticated user who created the event
--
-- How it works:
--   The DO block runs as the postgres superuser (bypasses RLS by default).
--   SET LOCAL ROLE authenticated  → activates RLS for the current transaction.
--   set_config('request.jwt.claim.sub', uid, true) → fakes auth.uid().
--   RESET ROLE                    → returns to postgres (superuser) for setup
--                                   and teardown steps.
--   ASSERT / RAISE EXCEPTION      → any failure aborts with a clear message.
--
-- Run against dev:
--   supabase db query \
--     --db-url "postgresql://postgres:<pw>@db.<ref>.supabase.co:5432/postgres" \
--     "$(cat supabase/tests/rls_suite.sql)"
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    -- Stable UUIDs that are easy to identify in logs
    v_owner_id      uuid := '00000001-0000-0000-0000-000000000000';
    v_vendor_id     uuid := '00000002-0000-0000-0000-000000000000';
    v_stranger_id   uuid := '00000003-0000-0000-0000-000000000000';
    v_event_id      uuid := '00000010-0000-0000-0000-000000000000';
    v_track_id      uuid := '00000011-0000-0000-0000-000000000000';
    v_block_id      uuid := '00000012-0000-0000-0000-000000000000';
    v_ev_id         uuid := '00000013-0000-0000-0000-000000000000'; -- event_vendors row

    v_count         bigint;
    v_ack           boolean;
    v_title         text;
BEGIN

    -- =========================================================================
    -- SETUP  (postgres superuser — RLS not enforced for our own inserts)
    -- =========================================================================

    -- Three test identities in auth.users (minimum required columns)
    INSERT INTO auth.users (id, email, aud, role, email_confirmed_at, created_at, updated_at)
    VALUES
        (v_owner_id,    'rls_owner@test.shift',    'authenticated', 'authenticated', now(), now(), now()),
        (v_vendor_id,   'rls_vendor@test.shift',   'authenticated', 'authenticated', now(), now(), now()),
        (v_stranger_id, 'rls_stranger@test.shift', 'authenticated', 'authenticated', now(), now(), now());

    INSERT INTO public.profiles (id, display_name, email, phone) VALUES
        (v_owner_id,    'RLS Owner',    'rls_owner@test.shift',    '+10000000001'),
        (v_vendor_id,   'RLS Vendor',   'rls_vendor@test.shift',   '+10000000002'),
        (v_stranger_id, 'RLS Stranger', 'rls_stranger@test.shift', '+10000000003');

    INSERT INTO public.events (id, owner_id, title, date)
    VALUES (v_event_id, v_owner_id, 'Original Event Title', now());

    INSERT INTO public.tracks (id, event_id, name, sort_order)
    VALUES (v_track_id, v_event_id, 'Main Track', 0);

    INSERT INTO public.blocks (id, track_id, event_id, title, scheduled_start, original_start, duration)
    VALUES (v_block_id, v_track_id, v_event_id, 'Original Title', now(), now(), 60);

    -- Vendor is an accepted collaborator (profile_id set, accepted_at set)
    INSERT INTO public.event_vendors (
        id, event_id, profile_id, display_name, role,
        notification_threshold, has_acknowledged_latest_shift, invited_at, accepted_at
    ) VALUES (
        v_ev_id, v_event_id, v_vendor_id, 'RLS Vendor', 'photographer',
        300, false, now(), now()
    );

    RAISE NOTICE '── Setup complete ──────────────────────────────────────────────────────';

    -- =========================================================================
    -- STRANGER: authenticated user with zero relationship to the event
    -- Expected: sees nothing; cannot write anything
    -- =========================================================================
    PERFORM set_config('request.jwt.claim.sub', v_stranger_id::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';

    SELECT count(*) INTO v_count FROM public.events;
    ASSERT v_count = 0, format('FAIL stranger/events: expected 0 rows, got %s', v_count);
    RAISE NOTICE 'PASS stranger: sees 0 events';

    SELECT count(*) INTO v_count FROM public.tracks;
    ASSERT v_count = 0, format('FAIL stranger/tracks: expected 0 rows, got %s', v_count);
    RAISE NOTICE 'PASS stranger: sees 0 tracks';

    SELECT count(*) INTO v_count FROM public.blocks;
    ASSERT v_count = 0, format('FAIL stranger/blocks: expected 0 rows, got %s', v_count);
    RAISE NOTICE 'PASS stranger: sees 0 blocks';

    SELECT count(*) INTO v_count FROM public.event_vendors;
    ASSERT v_count = 0, format('FAIL stranger/event_vendors: expected 0 rows, got %s', v_count);
    RAISE NOTICE 'PASS stranger: sees 0 event_vendors rows';

    SELECT count(*) INTO v_count FROM public.shift_records;
    ASSERT v_count = 0, format('FAIL stranger/shift_records: expected 0 rows, got %s', v_count);
    RAISE NOTICE 'PASS stranger: sees 0 shift_records';

    -- Cannot read another user''s full profile (self-only policy on profiles table)
    SELECT count(*) INTO v_count FROM public.profiles WHERE id = v_owner_id;
    ASSERT v_count = 0, format('FAIL stranger/profiles: expected 0 rows for other user, got %s', v_count);
    RAISE NOTICE 'PASS stranger: cannot read another user''s full profile row';

    -- CAN read public_profiles (the safe view; intentionally open for discovery)
    SELECT count(*) INTO v_count FROM public.public_profiles WHERE id = v_owner_id;
    ASSERT v_count = 1, format('FAIL stranger/public_profiles: expected 1 row, got %s', v_count);
    RAISE NOTICE 'PASS stranger: can read public_profiles (safe columns only)';

    -- Any authenticated user CAN create their own events (owner_id = auth.uid()) — that's by design.
    -- What a stranger CANNOT do is insert children into someone else's event.

    -- Cannot INSERT a track under another user's event
    BEGIN
        INSERT INTO public.tracks (event_id, name, sort_order)
        VALUES (v_event_id, 'stranger_track', 99);
        RAISE EXCEPTION 'FAIL stranger: INSERT track into another user''s event should be blocked';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS stranger: INSERT track into another user''s event blocked';
    END;

    -- Cannot INSERT a block under another user's event
    BEGIN
        INSERT INTO public.blocks (track_id, event_id, title, scheduled_start, original_start, duration)
        VALUES (v_track_id, v_event_id, 'stranger_block', now(), now(), 30);
        RAISE EXCEPTION 'FAIL stranger: INSERT block into another user''s event should be blocked';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS stranger: INSERT block into another user''s event blocked';
    END;

    -- Cannot impersonate: INSERT event with someone else''s owner_id
    BEGIN
        INSERT INTO public.events (id, owner_id, title, date)
        VALUES (gen_random_uuid(), v_owner_id, 'Impersonation Attempt', now());
        RAISE EXCEPTION 'FAIL stranger: INSERT event with another user''s owner_id should be blocked';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS stranger: INSERT event impersonating owner blocked';
    END;

    EXECUTE 'RESET ROLE';

    -- =========================================================================
    -- VENDOR: accepted collaborator — read timeline, cannot mutate it,
    --         can only flip own has_acknowledged_latest_shift
    -- =========================================================================
    PERFORM set_config('request.jwt.claim.sub', v_vendor_id::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';

    -- Can read the event and its children
    SELECT count(*) INTO v_count FROM public.events WHERE id = v_event_id;
    ASSERT v_count = 1, format('FAIL vendor/events: expected 1 row, got %s', v_count);
    RAISE NOTICE 'PASS vendor: reads the event';

    SELECT count(*) INTO v_count FROM public.tracks WHERE event_id = v_event_id;
    ASSERT v_count = 1, format('FAIL vendor/tracks: expected 1 row, got %s', v_count);
    RAISE NOTICE 'PASS vendor: reads tracks';

    SELECT count(*) INTO v_count FROM public.blocks WHERE event_id = v_event_id;
    ASSERT v_count = 1, format('FAIL vendor/blocks: expected 1 row, got %s', v_count);
    RAISE NOTICE 'PASS vendor: reads blocks';

    -- Can read own event_vendors row
    SELECT count(*) INTO v_count FROM public.event_vendors WHERE id = v_ev_id;
    ASSERT v_count = 1, format('FAIL vendor/event_vendors: expected 1 row, got %s', v_count);
    RAISE NOTICE 'PASS vendor: reads own event_vendors row';

    -- Cannot UPDATE blocks (row is invisible to UPDATE — USING clause blocks it; 0 affected rows)
    UPDATE public.blocks SET title = 'vendor_hacked' WHERE id = v_block_id;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    ASSERT v_count = 0, format('FAIL vendor/blocks UPDATE: expected 0 affected, got %s', v_count);
    RAISE NOTICE 'PASS vendor: block UPDATE affects 0 rows (RLS hides row from writes)';

    -- Cannot UPDATE tracks
    UPDATE public.tracks SET name = 'vendor_hacked' WHERE id = v_track_id;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    ASSERT v_count = 0, format('FAIL vendor/tracks UPDATE: expected 0 affected, got %s', v_count);
    RAISE NOTICE 'PASS vendor: track UPDATE affects 0 rows';

    -- Cannot UPDATE events
    UPDATE public.events SET title = 'vendor_hacked' WHERE id = v_event_id;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    ASSERT v_count = 0, format('FAIL vendor/events UPDATE: expected 0 affected, got %s', v_count);
    RAISE NOTICE 'PASS vendor: event UPDATE affects 0 rows';

    -- Cannot INSERT blocks
    BEGIN
        INSERT INTO public.blocks (id, track_id, event_id, title, scheduled_start, original_start, duration)
        VALUES (gen_random_uuid(), v_track_id, v_event_id, 'vendor_inserted', now(), now(), 30);
        RAISE EXCEPTION 'FAIL vendor: INSERT into blocks should have been blocked';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS vendor: INSERT into blocks blocked';
    END;

    -- CAN flip own ack (has_acknowledged_latest_shift — the one writable column)
    UPDATE public.event_vendors SET has_acknowledged_latest_shift = true WHERE id = v_ev_id;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    ASSERT v_count = 1, format('FAIL vendor/ack UPDATE: expected 1 affected, got %s', v_count);
    SELECT has_acknowledged_latest_shift INTO v_ack FROM public.event_vendors WHERE id = v_ev_id;
    ASSERT v_ack = true, 'FAIL vendor: ack not flipped to true after UPDATE';
    RAISE NOTICE 'PASS vendor: flipped own ack to true';

    -- Cannot change any other field on event_vendors (WITH CHECK rejects it)
    BEGIN
        UPDATE public.event_vendors SET role = 'hacked_role' WHERE id = v_ev_id;
        RAISE EXCEPTION 'FAIL vendor: changing role on event_vendors should have been rejected';
    EXCEPTION WHEN others THEN
        -- Postgres raises a policy violation when WITH CHECK fails
        IF SQLERRM ILIKE '%policy%' OR SQLERRM ILIKE '%check%' OR SQLERRM ILIKE '%rls%' THEN
            RAISE NOTICE 'PASS vendor: role change rejected by WITH CHECK policy';
        ELSE
            RAISE EXCEPTION 'FAIL vendor: unexpected error on role change: %', SQLERRM;
        END IF;
    END;

    BEGIN
        UPDATE public.event_vendors SET notification_threshold = 9999 WHERE id = v_ev_id;
        RAISE EXCEPTION 'FAIL vendor: changing notification_threshold should have been rejected';
    EXCEPTION WHEN others THEN
        IF SQLERRM ILIKE '%policy%' OR SQLERRM ILIKE '%check%' OR SQLERRM ILIKE '%rls%' THEN
            RAISE NOTICE 'PASS vendor: notification_threshold change rejected by WITH CHECK policy';
        ELSE
            RAISE EXCEPTION 'FAIL vendor: unexpected error on threshold change: %', SQLERRM;
        END IF;
    END;

    EXECUTE 'RESET ROLE';

    -- Post-vendor integrity check: block and event titles must be unchanged
    SELECT title INTO v_title FROM public.blocks WHERE id = v_block_id;
    ASSERT v_title = 'Original Title',
        format('FAIL: block title was mutated by vendor — got "%s"', v_title);
    RAISE NOTICE 'PASS integrity: block title still "Original Title" after vendor attempts';

    SELECT title INTO v_title FROM public.events WHERE id = v_event_id;
    ASSERT v_title = 'Original Event Title',
        format('FAIL: event title was mutated by vendor — got "%s"', v_title);
    RAISE NOTICE 'PASS integrity: event title unchanged after vendor attempts';

    -- =========================================================================
    -- OWNER: full control over all timeline tables
    -- =========================================================================
    PERFORM set_config('request.jwt.claim.sub', v_owner_id::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';

    -- Reads own event
    SELECT count(*) INTO v_count FROM public.events WHERE id = v_event_id;
    ASSERT v_count = 1, format('FAIL owner/events: expected 1 row, got %s', v_count);
    RAISE NOTICE 'PASS owner: reads the event';

    -- Updates event
    UPDATE public.events SET title = 'Owner Updated' WHERE id = v_event_id;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    ASSERT v_count = 1, format('FAIL owner/events UPDATE: expected 1 affected, got %s', v_count);
    RAISE NOTICE 'PASS owner: updated event';

    -- Updates block
    UPDATE public.blocks SET title = 'Owner Updated Block' WHERE id = v_block_id;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    ASSERT v_count = 1, format('FAIL owner/blocks UPDATE: expected 1 affected, got %s', v_count);
    RAISE NOTICE 'PASS owner: updated block';

    -- Inserts a new track
    INSERT INTO public.tracks (event_id, name, sort_order)
    VALUES (v_event_id, 'Owner Added Track', 1);
    GET DIAGNOSTICS v_count = ROW_COUNT;
    ASSERT v_count = 1, format('FAIL owner/tracks INSERT: expected 1 affected, got %s', v_count);
    RAISE NOTICE 'PASS owner: inserted a track';

    -- Updates event_vendors (any field — not just ack)
    UPDATE public.event_vendors SET notification_threshold = 600 WHERE id = v_ev_id;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    ASSERT v_count = 1, format('FAIL owner/event_vendors UPDATE: expected 1 affected, got %s', v_count);
    RAISE NOTICE 'PASS owner: updated event_vendors.notification_threshold';

    -- Deletes a block
    DELETE FROM public.blocks WHERE id = v_block_id;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    ASSERT v_count = 1, format('FAIL owner/blocks DELETE: expected 1 affected, got %s', v_count);
    RAISE NOTICE 'PASS owner: deleted block';

    EXECUTE 'RESET ROLE';

    -- =========================================================================
    -- CLEANUP (back as postgres superuser)
    -- Deleting auth.users cascades to profiles → events → tracks/blocks/vendors
    -- =========================================================================
    DELETE FROM auth.users WHERE id IN (v_owner_id, v_vendor_id, v_stranger_id);

    RAISE NOTICE '';
    RAISE NOTICE '═══════════════════════════════════════════════════════════════════════';
    RAISE NOTICE '  ALL RLS TESTS PASSED  ✓  (SHIFT-561)';
    RAISE NOTICE '═══════════════════════════════════════════════════════════════════════';

EXCEPTION WHEN OTHERS THEN
    -- Ensure we always clean up and restore role even on failure
    EXECUTE 'RESET ROLE';
    DELETE FROM auth.users WHERE id IN (v_owner_id, v_vendor_id, v_stranger_id);
    RAISE;  -- re-raise so the failure message surfaces
END;
$$;
