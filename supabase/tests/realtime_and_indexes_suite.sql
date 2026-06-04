-- SHIFT-564: Realtime-under-RLS and index-plan verification suite
--
-- Covers three verifications in a single DO block:
--
--   1. Publication membership  – all 7 collaboration tables are members of the
--                                supabase_realtime publication; device_tokens is not.
--
--   2. Realtime-under-RLS      – Supabase Realtime broadcasts a row change only to
--                                subscribers whose PostgreSQL SELECT policy passes for
--                                that row.  The DO block simulates a change (UPDATE as
--                                superuser) then verifies per-persona SELECT access:
--                                  vendor   → can SELECT → Realtime WOULD broadcast
--                                  stranger → cannot SELECT → Realtime SUPPRESSES
--                                This is the SQL-level equivalent of "subscriber
--                                receives changes only for accessible events."
--
--   3. Index existence          – every index from SHIFT-563 is present; the
--                                indexdef column confirms the correct column signature.
--
-- NOTE on full WebSocket coverage: asserting received WebSocket payloads requires
-- a live client (Supabase JS SDK, wscat, or supabase-js integration test).  This
-- suite proves the database-side invariants that Realtime depends on.
--
-- Run:
--   supabase db query \
--     --db-url "postgresql://postgres:<pw>@db.<ref>.supabase.co:5432/postgres" \
--     "$(cat supabase/tests/realtime_and_indexes_suite.sql)"
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    -- Distinct UUIDs from rls_suite.sql to allow both suites to run without collision.
    v_owner_id    uuid := '00000004-0000-0000-0000-000000000000';
    v_vendor_id   uuid := '00000005-0000-0000-0000-000000000000';
    v_stranger_id uuid := '00000006-0000-0000-0000-000000000000';
    v_event_id    uuid := '00000020-0000-0000-0000-000000000000';
    v_track_id    uuid := '00000021-0000-0000-0000-000000000000';
    v_block_id    uuid := '00000022-0000-0000-0000-000000000000';
    v_ev_id       uuid := '00000023-0000-0000-0000-000000000000';
    v_count       bigint;
    v_def         text;
BEGIN

    -- =========================================================================
    -- SETUP  (postgres superuser — RLS not enforced for our own inserts)
    -- =========================================================================
    INSERT INTO auth.users (id, email, aud, role, email_confirmed_at, created_at, updated_at)
    VALUES
        (v_owner_id,    'rt_owner@test.shift',    'authenticated', 'authenticated', now(), now(), now()),
        (v_vendor_id,   'rt_vendor@test.shift',   'authenticated', 'authenticated', now(), now(), now()),
        (v_stranger_id, 'rt_stranger@test.shift', 'authenticated', 'authenticated', now(), now(), now());

    INSERT INTO public.profiles (id, display_name, email, phone)
    VALUES
        (v_owner_id,    'RT Owner',    'rt_owner@test.shift',    '+10000000004'),
        (v_vendor_id,   'RT Vendor',   'rt_vendor@test.shift',   '+10000000005'),
        (v_stranger_id, 'RT Stranger', 'rt_stranger@test.shift', '+10000000006');

    INSERT INTO public.events (id, owner_id, title, date)
    VALUES (v_event_id, v_owner_id, 'RT Test Event', now());

    INSERT INTO public.tracks (id, event_id, name, sort_order)
    VALUES (v_track_id, v_event_id, 'RT Track', 0);

    INSERT INTO public.blocks (id, track_id, event_id, title, scheduled_start, original_start, duration)
    VALUES (v_block_id, v_track_id, v_event_id, 'Original RT Block', now(), now(), 60);

    -- Vendor is an accepted collaborator
    INSERT INTO public.event_vendors (
        id, event_id, profile_id, display_name, role,
        notification_threshold, has_acknowledged_latest_shift, invited_at, accepted_at
    ) VALUES (
        v_ev_id, v_event_id, v_vendor_id, 'RT Vendor', 'photographer',
        300, false, now(), now()
    );

    RAISE NOTICE '── Setup complete ──────────────────────────────────────────────────────';

    -- =========================================================================
    -- 1. PUBLICATION MEMBERSHIP
    -- =========================================================================
    RAISE NOTICE '── 1. Publication membership ────────────────────────────────────────────';

    -- All 7 collaboration tables must be in the publication
    SELECT count(*) INTO v_count
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename IN (
          'events', 'tracks', 'blocks', 'event_vendors',
          'block_vendors', 'block_dependencies', 'shift_records'
      );
    ASSERT v_count = 7,
        format(
            'FAIL: expected 7 tables in supabase_realtime, found %s. '
            'Diagnose: SELECT tablename FROM pg_publication_tables '
            'WHERE pubname = ''supabase_realtime'';',
            v_count
        );
    RAISE NOTICE 'PASS publication: all 7 collaboration tables are in supabase_realtime';

    -- device_tokens must NOT be in the publication (holds APNs secrets)
    SELECT count(*) INTO v_count
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'device_tokens';
    ASSERT v_count = 0, 'FAIL: device_tokens must not be in supabase_realtime (APNs secrets)';
    RAISE NOTICE 'PASS publication: device_tokens correctly excluded';

    -- =========================================================================
    -- 2. REALTIME UNDER RLS
    -- Simulate a change event then verify per-persona SELECT visibility.
    -- Realtime uses the same SELECT RLS predicate to decide whether to broadcast.
    -- =========================================================================
    RAISE NOTICE '── 2. Realtime-under-RLS ────────────────────────────────────────────────';

    -- Simulate the changes Realtime would broadcast (superuser write)
    UPDATE public.blocks SET title = 'Shifted RT Block' WHERE id = v_block_id;
    UPDATE public.events  SET status = 'live'            WHERE id = v_event_id;

    -- VENDOR: accepted collaborator — must be able to SELECT all updated rows.
    -- Realtime would broadcast these changes to the vendor's subscription.
    PERFORM set_config('request.jwt.claim.sub', v_vendor_id::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';

    SELECT count(*) INTO v_count FROM public.events WHERE id = v_event_id AND status = 'live';
    ASSERT v_count = 1, format('FAIL rt/vendor events: expected 1 row, got %s', v_count);
    RAISE NOTICE 'PASS rt: vendor sees updated event → Realtime would broadcast it';

    SELECT count(*) INTO v_count FROM public.blocks WHERE id = v_block_id AND title = 'Shifted RT Block';
    ASSERT v_count = 1, format('FAIL rt/vendor blocks: expected 1 row, got %s', v_count);
    RAISE NOTICE 'PASS rt: vendor sees updated block → Realtime would broadcast it';

    SELECT count(*) INTO v_count FROM public.tracks WHERE event_id = v_event_id;
    ASSERT v_count = 1, format('FAIL rt/vendor tracks: expected 1 row, got %s', v_count);
    RAISE NOTICE 'PASS rt: vendor sees tracks for the event';

    SELECT count(*) INTO v_count FROM public.event_vendors WHERE event_id = v_event_id;
    ASSERT v_count = 1, format('FAIL rt/vendor event_vendors: expected 1 row, got %s', v_count);
    RAISE NOTICE 'PASS rt: vendor sees own event_vendors row';

    EXECUTE 'RESET ROLE';

    -- STRANGER: no relationship to the event — must NOT see any row.
    -- Realtime would suppress all changes for this event from the stranger's subscription.
    PERFORM set_config('request.jwt.claim.sub', v_stranger_id::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';

    SELECT count(*) INTO v_count FROM public.events WHERE id = v_event_id;
    ASSERT v_count = 0, format('FAIL rt/stranger events: expected 0 rows, got %s', v_count);
    RAISE NOTICE 'PASS rt: stranger cannot SELECT event → Realtime would suppress it';

    SELECT count(*) INTO v_count FROM public.blocks WHERE id = v_block_id;
    ASSERT v_count = 0, format('FAIL rt/stranger blocks: expected 0 rows, got %s', v_count);
    RAISE NOTICE 'PASS rt: stranger cannot SELECT block → Realtime would suppress it';

    SELECT count(*) INTO v_count FROM public.tracks WHERE event_id = v_event_id;
    ASSERT v_count = 0, format('FAIL rt/stranger tracks: expected 0 rows, got %s', v_count);
    RAISE NOTICE 'PASS rt: stranger cannot SELECT tracks';

    SELECT count(*) INTO v_count FROM public.event_vendors WHERE event_id = v_event_id;
    ASSERT v_count = 0, format('FAIL rt/stranger event_vendors: expected 0 rows, got %s', v_count);
    RAISE NOTICE 'PASS rt: stranger cannot SELECT event_vendors';

    EXECUTE 'RESET ROLE';

    -- =========================================================================
    -- 3. INDEX EXISTENCE
    -- Check indexname + column signature via pg_indexes.indexdef.
    -- Two asserts per index: (a) the index exists, (b) column order is correct.
    -- =========================================================================
    RAISE NOTICE '── 3. Index existence ───────────────────────────────────────────────────';

    -- ── events ──
    v_def := (SELECT indexdef FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_events_owner_id_updated_at');
    ASSERT v_def IS NOT NULL,             'FAIL: idx_events_owner_id_updated_at missing';
    ASSERT v_def LIKE '%(owner_id, updated_at)%', format('FAIL wrong cols: %s', v_def);
    RAISE NOTICE 'PASS idx: idx_events_owner_id_updated_at';

    v_def := (SELECT indexdef FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_events_updated_at');
    ASSERT v_def IS NOT NULL,             'FAIL: idx_events_updated_at missing';
    ASSERT v_def LIKE '%(updated_at)%',   format('FAIL wrong cols: %s', v_def);
    RAISE NOTICE 'PASS idx: idx_events_updated_at';

    -- ── tracks ──
    v_def := (SELECT indexdef FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_tracks_event_id_updated_at');
    ASSERT v_def IS NOT NULL,                  'FAIL: idx_tracks_event_id_updated_at missing';
    ASSERT v_def LIKE '%(event_id, updated_at)%', format('FAIL wrong cols: %s', v_def);
    RAISE NOTICE 'PASS idx: idx_tracks_event_id_updated_at';

    -- ── blocks ──
    v_def := (SELECT indexdef FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_blocks_event_id_updated_at');
    ASSERT v_def IS NOT NULL,                  'FAIL: idx_blocks_event_id_updated_at missing';
    ASSERT v_def LIKE '%(event_id, updated_at)%', format('FAIL wrong cols: %s', v_def);
    RAISE NOTICE 'PASS idx: idx_blocks_event_id_updated_at';

    v_def := (SELECT indexdef FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_blocks_track_id');
    ASSERT v_def IS NOT NULL,           'FAIL: idx_blocks_track_id missing';
    ASSERT v_def LIKE '%(track_id)%',   format('FAIL wrong cols: %s', v_def);
    RAISE NOTICE 'PASS idx: idx_blocks_track_id';

    -- ── event_vendors ──
    v_def := (SELECT indexdef FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_event_vendors_event_id_updated_at');
    ASSERT v_def IS NOT NULL,                  'FAIL: idx_event_vendors_event_id_updated_at missing';
    ASSERT v_def LIKE '%(event_id, updated_at)%', format('FAIL wrong cols: %s', v_def);
    RAISE NOTICE 'PASS idx: idx_event_vendors_event_id_updated_at';

    v_def := (SELECT indexdef FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_event_vendors_profile_id');
    ASSERT v_def IS NOT NULL,             'FAIL: idx_event_vendors_profile_id missing';
    ASSERT v_def LIKE '%(profile_id)%',   format('FAIL wrong cols: %s', v_def);
    RAISE NOTICE 'PASS idx: idx_event_vendors_profile_id';

    -- ── block_vendors ──
    v_def := (SELECT indexdef FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_block_vendors_event_id');
    ASSERT v_def IS NOT NULL,           'FAIL: idx_block_vendors_event_id missing';
    ASSERT v_def LIKE '%(event_id)%',   format('FAIL wrong cols: %s', v_def);
    RAISE NOTICE 'PASS idx: idx_block_vendors_event_id';

    v_def := (SELECT indexdef FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_block_vendors_event_vendor_id');
    ASSERT v_def IS NOT NULL,                   'FAIL: idx_block_vendors_event_vendor_id missing';
    ASSERT v_def LIKE '%(event_vendor_id)%',    format('FAIL wrong cols: %s', v_def);
    RAISE NOTICE 'PASS idx: idx_block_vendors_event_vendor_id';

    -- ── block_dependencies ──
    v_def := (SELECT indexdef FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_block_dependencies_event_id');
    ASSERT v_def IS NOT NULL,           'FAIL: idx_block_dependencies_event_id missing';
    ASSERT v_def LIKE '%(event_id)%',   format('FAIL wrong cols: %s', v_def);
    RAISE NOTICE 'PASS idx: idx_block_dependencies_event_id';

    v_def := (SELECT indexdef FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_block_dependencies_depends_on_block_id');
    ASSERT v_def IS NOT NULL,                       'FAIL: idx_block_dependencies_depends_on_block_id missing';
    ASSERT v_def LIKE '%(depends_on_block_id)%',    format('FAIL wrong cols: %s', v_def);
    RAISE NOTICE 'PASS idx: idx_block_dependencies_depends_on_block_id';

    -- ── shift_records ──
    v_def := (SELECT indexdef FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_shift_records_event_id_updated_at');
    ASSERT v_def IS NOT NULL,                  'FAIL: idx_shift_records_event_id_updated_at missing';
    ASSERT v_def LIKE '%(event_id, updated_at)%', format('FAIL wrong cols: %s', v_def);
    RAISE NOTICE 'PASS idx: idx_shift_records_event_id_updated_at';

    -- Partial index: check column + WHERE predicate presence
    v_def := (SELECT indexdef FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_shift_records_source_block_id');
    ASSERT v_def IS NOT NULL,                   'FAIL: idx_shift_records_source_block_id missing';
    ASSERT v_def LIKE '%(source_block_id)%',    format('FAIL wrong cols: %s', v_def);
    ASSERT lower(v_def) LIKE '%where%',         format('FAIL: partial predicate missing from indexdef: %s', v_def);
    RAISE NOTICE 'PASS idx: idx_shift_records_source_block_id (partial, WHERE source_block_id IS NOT NULL)';

    -- =========================================================================
    -- CLEANUP
    -- Deleting auth.users cascades to profiles → events → all children
    -- =========================================================================
    DELETE FROM auth.users WHERE id IN (v_owner_id, v_vendor_id, v_stranger_id);

    RAISE NOTICE '';
    RAISE NOTICE '═══════════════════════════════════════════════════════════════════════';
    RAISE NOTICE '  ALL REALTIME + INDEX TESTS PASSED  ✓  (SHIFT-564)';
    RAISE NOTICE '═══════════════════════════════════════════════════════════════════════';

EXCEPTION WHEN OTHERS THEN
    EXECUTE 'RESET ROLE';
    DELETE FROM auth.users WHERE id IN (v_owner_id, v_vendor_id, v_stranger_id);
    RAISE;
END;
$$;

-- ============================================================================
-- EXPLAIN VERIFICATION
-- Standalone queries run after the DO block.  enable_seqscan = off forces the
-- planner to choose an index plan regardless of table size, proving each index
-- is correctly defined for its query.  Inspect the output for:
--   "Index Scan using <index_name> on <table>"
-- ============================================================================

SET enable_seqscan = off;

-- ── events: owner hydration (prefix scan) ────────────────────────────────────
EXPLAIN SELECT * FROM public.events
WHERE owner_id = '00000004-0000-0000-0000-000000000000';
-- CHECK: Index Scan using idx_events_owner_id_updated_at on events

-- ── events: owner delta (full compound predicate) ────────────────────────────
EXPLAIN SELECT * FROM public.events
WHERE owner_id    = '00000004-0000-0000-0000-000000000000'
  AND updated_at  > now() - interval '1 hour';
-- CHECK: Index Scan using idx_events_owner_id_updated_at on events

-- ── tracks: hydration (prefix) ───────────────────────────────────────────────
EXPLAIN SELECT * FROM public.tracks
WHERE event_id = '00000020-0000-0000-0000-000000000000';
-- CHECK: Index Scan using idx_tracks_event_id_updated_at on tracks

-- ── tracks: delta ────────────────────────────────────────────────────────────
EXPLAIN SELECT * FROM public.tracks
WHERE event_id   = '00000020-0000-0000-0000-000000000000'
  AND updated_at > now() - interval '1 hour';
-- CHECK: Index Scan using idx_tracks_event_id_updated_at on tracks

-- ── blocks: hydration / Realtime channel filter ──────────────────────────────
EXPLAIN SELECT * FROM public.blocks
WHERE event_id = '00000020-0000-0000-0000-000000000000';
-- CHECK: Index Scan using idx_blocks_event_id_updated_at on blocks

-- ── blocks: delta ────────────────────────────────────────────────────────────
EXPLAIN SELECT * FROM public.blocks
WHERE event_id   = '00000020-0000-0000-0000-000000000000'
  AND updated_at > now() - interval '1 hour';
-- CHECK: Index Scan using idx_blocks_event_id_updated_at on blocks

-- ── event_vendors: claim-on-sign-in + RLS lookup ────────────────────────────
EXPLAIN SELECT * FROM public.event_vendors
WHERE profile_id = '00000005-0000-0000-0000-000000000000';
-- CHECK: Index Scan using idx_event_vendors_profile_id on event_vendors

-- ── event_vendors: delta ─────────────────────────────────────────────────────
EXPLAIN SELECT * FROM public.event_vendors
WHERE event_id   = '00000020-0000-0000-0000-000000000000'
  AND updated_at > now() - interval '1 hour';
-- CHECK: Index Scan using idx_event_vendors_event_id_updated_at on event_vendors

-- ── shift_records: delta ─────────────────────────────────────────────────────
EXPLAIN SELECT * FROM public.shift_records
WHERE event_id   = '00000020-0000-0000-0000-000000000000'
  AND updated_at > now() - interval '1 hour';
-- CHECK: Index Scan using idx_shift_records_event_id_updated_at on shift_records

-- ── block_vendors: Realtime channel filter ───────────────────────────────────
EXPLAIN SELECT * FROM public.block_vendors
WHERE event_id = '00000020-0000-0000-0000-000000000000';
-- CHECK: Index Scan using idx_block_vendors_event_id on block_vendors

-- ── block_dependencies: Realtime channel filter ──────────────────────────────
EXPLAIN SELECT * FROM public.block_dependencies
WHERE event_id = '00000020-0000-0000-0000-000000000000';
-- CHECK: Index Scan using idx_block_dependencies_event_id on block_dependencies

RESET enable_seqscan;
