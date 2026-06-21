-- Verification for E17 Story 2 stat triggers + vendor_public_stats view.
--
-- Self-contained: seeds fixtures, exercises the rating recompute, the
-- events-completed bump, and the profile-detail view, then ROLLs BACK.
-- Run: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/vendor_review_stats_test.sql
-- Clean run ends with "ALL STATS TESTS PASSED".

begin;

set local client_min_messages = notice;

do $$
declare
    v_owner1 uuid := gen_random_uuid();
    v_owner2 uuid := gen_random_uuid();
    v_vendor uuid := gen_random_uuid();
    v_e1     uuid := gen_random_uuid();
    v_e2     uuid := gen_random_uuid();
    v_count  int;
    v_avg    numeric;
    v_completed int;
    v_stat   record;
begin
    -- ── Fixtures ──────────────────────────────────────────────────────────────
    insert into auth.users (id) values (v_owner1), (v_owner2), (v_vendor);
    insert into public.profiles (id, display_name) values
        (v_owner1, 'Owner One'), (v_owner2, 'Owner Two'), (v_vendor, 'Vendor');
    insert into public.vendor_profiles (profile_id, is_listed) values (v_vendor, true);

    -- Two events by two different planners; start in 'planning' so completing
    -- them later fires the events-completed trigger.
    insert into public.events (id, owner_id, title, date, status) values
        (v_e1, v_owner1, 'Event 1', now(), 'planning'),
        (v_e2, v_owner2, 'Event 2', now(), 'planning');

    -- Vendor claimed both. E1 ended clean (acked); E2 ended dirty (not acked +
    -- a pending delta) so reliability should be 50%.
    insert into public.event_vendors
        (event_id, profile_id, display_name, role, accepted_at, has_acknowledged_latest_shift, pending_shift_delta)
    values
        (v_e1, v_vendor, 'Vendor', 'dj', now(), true,  null),
        (v_e2, v_vendor, 'Vendor', 'dj', now(), false, 600);

    -- ── Events-completed trigger ─────────────────────────────────────────────
    update public.events set status = 'completed', completed_at = now()
        where id in (v_e1, v_e2);

    select events_completed_count into v_completed
        from public.vendor_profiles where profile_id = v_vendor;
    if v_completed <> 2 then
        raise exception 'events_completed_count expected 2, got %', v_completed;
    end if;
    raise notice 'events_completed_count = 2 OK';

    -- Re-completing must NOT double-count (guard on old.status <> completed).
    update public.events set status = 'completed' where id = v_e1;  -- no-op transition
    select events_completed_count into v_completed
        from public.vendor_profiles where profile_id = v_vendor;
    if v_completed <> 2 then
        raise exception 'events_completed_count double-counted: %', v_completed;
    end if;
    raise notice 'no double-count on completed->completed OK';

    -- ── Rating recompute trigger (via the RPC) ───────────────────────────────
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner1::text)::text, true);
    perform public.submit_vendor_review(v_e1, v_vendor, 4::smallint, 'great');
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner2::text)::text, true);
    perform public.submit_vendor_review(v_e2, v_vendor, 2::smallint, 'ok');

    select rating_count, rating_avg into v_count, v_avg
        from public.vendor_profiles where profile_id = v_vendor;
    if v_count <> 2 or v_avg <> 3.00 then
        raise exception 'expected count=2 avg=3.00, got count=% avg=%', v_count, v_avg;
    end if;
    raise notice 'rating_count=2 rating_avg=3.00 OK';

    -- Soft-deleting a review recomputes down (count=1, avg=4.00).
    update public.vendor_reviews set deleted_at = now()
        where event_id = v_e2 and vendor_profile_id = v_vendor;
    select rating_count, rating_avg into v_count, v_avg
        from public.vendor_profiles where profile_id = v_vendor;
    if v_count <> 1 or v_avg <> 4.00 then
        raise exception 'after soft-delete expected count=1 avg=4.00, got count=% avg=%', v_count, v_avg;
    end if;
    raise notice 'after soft-delete rating_count=1 rating_avg=4.00 OK';

    -- ── vendor_public_stats view ─────────────────────────────────────────────
    select * into v_stat from public.vendor_public_stats where profile_id = v_vendor;
    if v_stat.events_completed <> 2 then
        raise exception 'stats.events_completed expected 2, got %', v_stat.events_completed;
    end if;
    if v_stat.repeat_planner_count <> 0 then
        raise exception 'stats.repeat_planner_count expected 0, got %', v_stat.repeat_planner_count;
    end if;
    if v_stat.reliability_pct <> 50 then
        raise exception 'stats.reliability_pct expected 50, got %', v_stat.reliability_pct;
    end if;
    raise notice 'vendor_public_stats events=2 repeat=0 reliability=50 OK';

    raise notice 'ALL STATS TESTS PASSED';
end;
$$;

rollback;
