-- Gate tests for submit_vendor_review (E17 Story 1).
--
-- Self-contained: seeds fixtures, simulates auth via request.jwt.claims (what
-- auth.uid() reads), exercises every gate, and ROLLs BACK so it leaves no trace.
-- Run against a local stack:  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f \
--   supabase/tests/vendor_reviews_gate_test.sql
-- It RAISE EXCEPTIONs on the first failed assertion (and ON_ERROR_STOP aborts);
-- a clean run prints the NOTICE lines and ends with "ALL GATE TESTS PASSED".
--
-- Cases:
--   1. Non-completed event is rejected (status = 'planning').
--   2. A vendor who never worked the event is rejected (no claimed row).
--   3. Happy path inserts exactly one review.
--   4. A duplicate (event, vendor) is blocked by the unique constraint (23505).

begin;

set local client_min_messages = notice;

do $$
declare
    v_owner   uuid := gen_random_uuid();   -- event planner / reviewer
    v_vendor  uuid := gen_random_uuid();   -- vendor who worked the event
    v_other   uuid := gen_random_uuid();   -- vendor who never worked the event
    v_event   uuid := gen_random_uuid();
    v_caught  boolean;
    v_count   int;
begin
    -- ── Fixtures ──────────────────────────────────────────────────────────────
    insert into auth.users (id) values (v_owner), (v_vendor), (v_other);

    insert into public.profiles (id, display_name) values
        (v_owner,  'Owner'),
        (v_vendor, 'Vendor'),
        (v_other,  'Other Vendor');

    -- Both vendors are listed so the public_select path is exercisable later.
    insert into public.vendor_profiles (profile_id, is_listed) values
        (v_vendor, true),
        (v_other,  true);

    -- Event starts in 'planning' for case 1; flipped to 'completed' afterwards.
    insert into public.events (id, owner_id, title, date, status)
        values (v_event, v_owner, 'Test Event', now(), 'planning');

    -- v_vendor claimed the event (accepted_at set); v_other never did.
    insert into public.event_vendors (event_id, profile_id, display_name, role, accepted_at)
        values (v_event, v_vendor, 'Vendor', 'photographer', now());

    -- Act as the owner for every RPC call below.
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_owner::text)::text, true);

    -- ── Case 1: non-completed event rejected ─────────────────────────────────
    v_caught := false;
    begin
        perform public.submit_vendor_review(v_event, v_vendor, 5::smallint, 'great');
    exception when others then
        v_caught := true;
        raise notice 'case 1 rejected as expected: %', sqlerrm;
    end;
    if not v_caught then
        raise exception 'CASE 1 FAILED: review accepted on a non-completed event';
    end if;

    -- Complete the event for the remaining cases.
    update public.events set status = 'completed', completed_at = now()
        where id = v_event;

    -- ── Case 2: vendor who never worked the event rejected ───────────────────
    v_caught := false;
    begin
        perform public.submit_vendor_review(v_event, v_other, 5::smallint, 'nope');
    exception when others then
        v_caught := true;
        raise notice 'case 2 rejected as expected: %', sqlerrm;
    end;
    if not v_caught then
        raise exception 'CASE 2 FAILED: review accepted for a vendor who never worked the event';
    end if;

    -- ── Case 3: happy path inserts one review ────────────────────────────────
    perform public.submit_vendor_review(v_event, v_vendor, 4::smallint, 'solid work');
    select count(*) into v_count
        from public.vendor_reviews
        where event_id = v_event and vendor_profile_id = v_vendor;
    if v_count <> 1 then
        raise exception 'CASE 3 FAILED: expected exactly 1 review, found %', v_count;
    end if;
    raise notice 'case 3 inserted one review as expected';

    -- ── Case 4: duplicate blocked by the unique constraint ───────────────────
    v_caught := false;
    begin
        perform public.submit_vendor_review(v_event, v_vendor, 3::smallint, 'again');
    exception when unique_violation then
        v_caught := true;
        raise notice 'case 4 blocked by unique constraint as expected';
    end;
    if not v_caught then
        raise exception 'CASE 4 FAILED: duplicate review was not blocked';
    end if;

    raise notice 'ALL GATE TESTS PASSED';
end;
$$;

rollback;
