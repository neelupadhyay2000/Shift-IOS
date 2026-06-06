-- SHIFT-643: shift-notify trigger wiring verification suite
--
-- Proves the database-side invariants that make a qualifying shift fire the
-- Edge Function:
--   1. pg_net is installed (net.http_post is available).
--   2. notify_shift_delta() exists and is SECURITY DEFINER (so it can read Vault).
--   3. trg_notify_shift_delta is AFTER UPDATE OF pending_shift_delta, FOR EACH ROW,
--      carries a WHEN guard, and executes notify_shift_delta().
--
-- The actual HTTP enqueue + APNs send is network-side (like the WebSocket caveat
-- in realtime_and_indexes_suite.sql). Verify it manually after setting the Vault
-- secrets — see the "Manual behavioral verification" note at the bottom.
--
-- Run:
--   supabase db query \
--     --db-url "postgresql://postgres:<pw>@db.<ref>.supabase.co:5432/postgres" \
--     "$(cat supabase/tests/shift_notify_trigger_suite.sql)"
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_secdef    boolean;
    v_def       text;
BEGIN
    -- 1. pg_net installed ----------------------------------------------------
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
        RAISE EXCEPTION 'FAIL: pg_net extension is not installed';
    END IF;

    -- 2. function exists + is SECURITY DEFINER -------------------------------
    SELECT prosecdef INTO v_secdef
        FROM pg_proc
        WHERE pronamespace = 'public'::regnamespace
          AND proname = 'notify_shift_delta';

    IF v_secdef IS NULL THEN
        RAISE EXCEPTION 'FAIL: function public.notify_shift_delta() does not exist';
    END IF;
    IF v_secdef IS NOT TRUE THEN
        RAISE EXCEPTION 'FAIL: notify_shift_delta() must be SECURITY DEFINER (to read Vault)';
    END IF;

    -- 3. trigger is correctly scoped -----------------------------------------
    SELECT pg_get_triggerdef(t.oid) INTO v_def
        FROM pg_trigger t
        WHERE t.tgrelid = 'public.event_vendors'::regclass
          AND t.tgname = 'trg_notify_shift_delta';

    IF v_def IS NULL THEN
        RAISE EXCEPTION 'FAIL: trigger trg_notify_shift_delta is missing on event_vendors';
    END IF;
    IF position('AFTER UPDATE OF pending_shift_delta' IN v_def) = 0 THEN
        RAISE EXCEPTION 'FAIL: trigger must be AFTER UPDATE OF pending_shift_delta. Got: %', v_def;
    END IF;
    IF position('FOR EACH ROW' IN v_def) = 0 THEN
        RAISE EXCEPTION 'FAIL: trigger must be row-level (FOR EACH ROW). Got: %', v_def;
    END IF;
    IF position('WHEN' IN v_def) = 0 THEN
        RAISE EXCEPTION 'FAIL: trigger must carry a WHEN guard. Got: %', v_def;
    END IF;
    IF position('notify_shift_delta()' IN v_def) = 0 THEN
        RAISE EXCEPTION 'FAIL: trigger must execute notify_shift_delta(). Got: %', v_def;
    END IF;

    RAISE NOTICE 'PASS: shift-notify trigger is installed and correctly scoped.';
END $$;

-- ---------------------------------------------------------------------------
-- Manual behavioral verification (requires the Vault secrets, SHIFT-643 deploy):
--
--   -- after: select vault.create_secret('https://<ref>.supabase.co','project_url');
--   --        select vault.create_secret('<service_role_key>','service_role_key');
--
--   -- qualifying shift on a claimed vendor → exactly one queued request:
--   update public.event_vendors
--      set pending_shift_delta = 900
--    where profile_id is not null
--    limit 1;
--
--   -- the request fires asynchronously; inspect the result (200 once the
--   -- shift-notify function from SHIFT-644 is deployed; 404 before then —
--   -- either way proves the trigger invoked the Edge Function):
--   select id, status_code, created
--     from net._http_response
--    order by created desc
--    limit 5;
--
--   -- negative: re-running the same value, or an ack-only write, enqueues nothing.
-- ---------------------------------------------------------------------------
