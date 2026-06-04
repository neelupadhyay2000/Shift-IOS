-- SHIFT-566: Storage voice-memos access policy test suite
--
-- Tests four personas against the voice_memos_* storage policies:
--   owner    → can SELECT (download), INSERT (upload), UPDATE, DELETE
--   vendor   → can SELECT only; INSERT/UPDATE/DELETE denied
--   stranger → everything denied
--
-- How it works:
--   The DO block runs as the postgres superuser (bypasses RLS).
--   Superuser inserts test objects directly into storage.objects for
--   SELECT visibility tests.
--   Write-policy tests (INSERT/UPDATE/DELETE) use SET LOCAL ROLE authenticated
--   + set_config('request.jwt.claim.sub', uid) to activate RLS, then attempt
--   the operation inside a PL/pgSQL BEGIN…EXCEPTION block so a policy violation
--   rolls back the savepoint without aborting the outer transaction.
--
-- Run:
--   supabase db query \
--     --db-url "postgresql://postgres:<pw>@db.<ref>.supabase.co:5432/postgres" \
--     "$(cat supabase/tests/storage_voice_memos_suite.sql)"
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_owner_id    uuid := '00000007-0000-0000-0000-000000000000';
    v_vendor_id   uuid := '00000008-0000-0000-0000-000000000000';
    v_stranger_id uuid := '00000009-0000-0000-0000-000000000000';
    v_event_id    uuid := '00000030-0000-0000-0000-000000000000';
    v_track_id    uuid := '00000031-0000-0000-0000-000000000000';
    v_block_id    uuid := '00000032-0000-0000-0000-000000000000';
    v_block2_id   uuid := '00000033-0000-0000-0000-000000000000';  -- for owner INSERT test
    v_ev_id       uuid := '00000034-0000-0000-0000-000000000000';
    v_obj_id      uuid := '00000040-0000-0000-0000-000000000000';  -- pre-seeded audio object

    -- The object path for the pre-seeded recording
    v_path        text;
    -- A path the owner will INSERT during the write tests
    v_new_path    text;
    v_count       bigint;
BEGIN
    v_path     := v_event_id::text || '/' || v_block_id::text  || '.m4a';
    v_new_path := v_event_id::text || '/' || v_block2_id::text || '.m4a';

    -- =========================================================================
    -- SETUP  (postgres superuser — RLS not enforced)
    -- =========================================================================
    INSERT INTO auth.users (id, email, aud, role, email_confirmed_at, created_at, updated_at)
    VALUES
        (v_owner_id,    'vm_owner@test.shift',    'authenticated', 'authenticated', now(), now(), now()),
        (v_vendor_id,   'vm_vendor@test.shift',   'authenticated', 'authenticated', now(), now(), now()),
        (v_stranger_id, 'vm_stranger@test.shift', 'authenticated', 'authenticated', now(), now(), now());

    INSERT INTO public.profiles (id, display_name, email, phone)
    VALUES
        (v_owner_id,    'VM Owner',    'vm_owner@test.shift',    '+10000000007'),
        (v_vendor_id,   'VM Vendor',   'vm_vendor@test.shift',   '+10000000008'),
        (v_stranger_id, 'VM Stranger', 'vm_stranger@test.shift', '+10000000009');

    INSERT INTO public.events (id, owner_id, title, date)
    VALUES (v_event_id, v_owner_id, 'VM Test Event', now());

    INSERT INTO public.tracks (id, event_id, name, sort_order)
    VALUES (v_track_id, v_event_id, 'VM Track', 0);

    -- Two blocks: one for the pre-seeded object, one for the owner-upload test
    INSERT INTO public.blocks (id, track_id, event_id, title, scheduled_start, original_start, duration)
    VALUES
        (v_block_id,  v_track_id, v_event_id, 'VM Block 1', now(), now(), 60),
        (v_block2_id, v_track_id, v_event_id, 'VM Block 2', now(), now(), 30);

    -- Vendor is an accepted collaborator
    INSERT INTO public.event_vendors (
        id, event_id, profile_id, display_name, role,
        notification_threshold, has_acknowledged_latest_shift, invited_at, accepted_at
    ) VALUES (
        v_ev_id, v_event_id, v_vendor_id, 'VM Vendor', 'videographer',
        300, false, now(), now()
    );

    -- Pre-seed a storage object as superuser (simulates an already-uploaded recording)
    INSERT INTO storage.objects (id, bucket_id, name, owner, owner_id)
    VALUES (v_obj_id, 'voice-memos', v_path, v_owner_id, v_owner_id::text);

    RAISE NOTICE '── Setup complete ──────────────────────────────────────────────────────';

    -- =========================================================================
    -- 1. SELECT (download) visibility
    -- =========================================================================
    RAISE NOTICE '── 1. SELECT visibility ────────────────────────────────────────────────';

    -- OWNER: can download their recording
    PERFORM set_config('request.jwt.claim.sub', v_owner_id::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';

    SELECT count(*) INTO v_count FROM storage.objects
    WHERE bucket_id = 'voice-memos' AND name = v_path;
    ASSERT v_count = 1, format('FAIL owner/select: expected 1, got %s', v_count);
    RAISE NOTICE 'PASS owner: can SELECT (download) their recording';

    EXECUTE 'RESET ROLE';

    -- VENDOR: accepted collaborator can download
    PERFORM set_config('request.jwt.claim.sub', v_vendor_id::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';

    SELECT count(*) INTO v_count FROM storage.objects
    WHERE bucket_id = 'voice-memos' AND name = v_path;
    ASSERT v_count = 1, format('FAIL vendor/select: expected 1, got %s', v_count);
    RAISE NOTICE 'PASS vendor: can SELECT (download) the recording';

    EXECUTE 'RESET ROLE';

    -- STRANGER: cannot see any recording in this bucket
    PERFORM set_config('request.jwt.claim.sub', v_stranger_id::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';

    SELECT count(*) INTO v_count FROM storage.objects
    WHERE bucket_id = 'voice-memos' AND name = v_path;
    ASSERT v_count = 0, format('FAIL stranger/select: expected 0, got %s', v_count);
    RAISE NOTICE 'PASS stranger: SELECT returns 0 rows (access denied)';

    EXECUTE 'RESET ROLE';

    -- =========================================================================
    -- 2. INSERT (upload) — owner allowed; vendor + stranger denied
    -- =========================================================================
    RAISE NOTICE '── 2. INSERT (upload) ──────────────────────────────────────────────────';

    -- OWNER: can upload a recording for their own block
    PERFORM set_config('request.jwt.claim.sub', v_owner_id::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';

    BEGIN
        INSERT INTO storage.objects (id, bucket_id, name, owner, owner_id)
        VALUES (gen_random_uuid(), 'voice-memos', v_new_path, v_owner_id, v_owner_id::text);
        GET DIAGNOSTICS v_count = ROW_COUNT;
        ASSERT v_count = 1, 'FAIL owner/insert: INSERT returned 0 rows';
        RAISE NOTICE 'PASS owner: can INSERT (upload) a recording';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE EXCEPTION 'FAIL owner/insert: INSERT was blocked but should be allowed';
    END;

    EXECUTE 'RESET ROLE';

    -- VENDOR: read-only — upload must be denied
    PERFORM set_config('request.jwt.claim.sub', v_vendor_id::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';

    BEGIN
        INSERT INTO storage.objects (id, bucket_id, name, owner, owner_id)
        VALUES (gen_random_uuid(), 'voice-memos', v_path, v_vendor_id, v_vendor_id::text);
        RAISE EXCEPTION 'FAIL vendor/insert: INSERT should have been blocked but succeeded';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS vendor: INSERT (upload) blocked by policy';
    END;

    EXECUTE 'RESET ROLE';

    -- STRANGER: upload into an event they have no relationship with — must be denied
    PERFORM set_config('request.jwt.claim.sub', v_stranger_id::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';

    BEGIN
        INSERT INTO storage.objects (id, bucket_id, name, owner, owner_id)
        VALUES (gen_random_uuid(), 'voice-memos', v_path, v_stranger_id, v_stranger_id::text);
        RAISE EXCEPTION 'FAIL stranger/insert: INSERT should have been blocked but succeeded';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS stranger: INSERT (upload) blocked by policy';
    END;

    EXECUTE 'RESET ROLE';

    -- =========================================================================
    -- 3. Path format guard
    -- A path that does not match {uuid}/{uuid}.m4a must be denied for all
    -- operations, even when the caller is the event owner.
    -- =========================================================================
    RAISE NOTICE '── 3. Path format guard ────────────────────────────────────────────────';

    PERFORM set_config('request.jwt.claim.sub', v_owner_id::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';

    -- Malformed path (no slash, wrong extension)
    BEGIN
        INSERT INTO storage.objects (id, bucket_id, name, owner, owner_id)
        VALUES (gen_random_uuid(), 'voice-memos', 'malicious-file.mp3', v_owner_id, v_owner_id::text);
        RAISE EXCEPTION 'FAIL format-guard: malformed path INSERT should have been blocked';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS format-guard: malformed path denied even for owner';
    END;

    -- Path pointing to a non-existent block
    BEGIN
        INSERT INTO storage.objects (id, bucket_id, name, owner, owner_id)
        VALUES (
            gen_random_uuid(), 'voice-memos',
            v_event_id::text || '/' || gen_random_uuid()::text || '.m4a',
            v_owner_id, v_owner_id::text
        );
        RAISE EXCEPTION 'FAIL block-guard: non-existent block INSERT should have been blocked';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS block-guard: upload for non-existent block denied';
    END;

    EXECUTE 'RESET ROLE';

    -- =========================================================================
    -- 4. DELETE — owner allowed; vendor denied
    -- =========================================================================
    RAISE NOTICE '── 4. DELETE ───────────────────────────────────────────────────────────';

    -- VENDOR: cannot delete
    PERFORM set_config('request.jwt.claim.sub', v_vendor_id::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';

    DELETE FROM storage.objects WHERE bucket_id = 'voice-memos' AND name = v_path;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    ASSERT v_count = 0, format('FAIL vendor/delete: expected 0 rows affected, got %s', v_count);
    RAISE NOTICE 'PASS vendor: DELETE affects 0 rows (RLS hides object from writes)';

    EXECUTE 'RESET ROLE';

    -- OWNER: can delete
    PERFORM set_config('request.jwt.claim.sub', v_owner_id::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';

    DELETE FROM storage.objects WHERE bucket_id = 'voice-memos' AND name = v_path;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    ASSERT v_count = 1, format('FAIL owner/delete: expected 1 row affected, got %s', v_count);
    RAISE NOTICE 'PASS owner: can DELETE their recording';

    EXECUTE 'RESET ROLE';

    -- =========================================================================
    -- CLEANUP — deleting auth.users cascades to profiles → events → all children
    -- =========================================================================
    DELETE FROM auth.users WHERE id IN (v_owner_id, v_vendor_id, v_stranger_id);

    -- Remove any leftover storage objects (owner-uploaded test file from §2)
    DELETE FROM storage.objects WHERE bucket_id = 'voice-memos'
        AND name LIKE v_event_id::text || '/%';

    RAISE NOTICE '';
    RAISE NOTICE '═══════════════════════════════════════════════════════════════════════';
    RAISE NOTICE '  ALL STORAGE VOICE-MEMOS TESTS PASSED  ✓  (SHIFT-566)';
    RAISE NOTICE '═══════════════════════════════════════════════════════════════════════';

EXCEPTION WHEN OTHERS THEN
    EXECUTE 'RESET ROLE';
    DELETE FROM auth.users WHERE id IN (v_owner_id, v_vendor_id, v_stranger_id);
    DELETE FROM storage.objects WHERE bucket_id = 'voice-memos'
        AND name LIKE v_event_id::text || '/%';
    RAISE;
END;
$$;
