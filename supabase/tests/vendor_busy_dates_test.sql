-- Verification for E18 Story 1: vendor_busy_dates RLS + get_my_calendar.
-- Self-contained, transactional (ROLLBACK). Run:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/vendor_busy_dates_test.sql
-- Clean run ends with "ALL AVAILABILITY TESTS PASSED".

begin;

set local client_min_messages = notice;

do $$
declare
    v_vendor uuid := gen_random_uuid();
    v_owner  uuid := gen_random_uuid();
    v_other  uuid := gen_random_uuid();
    v_event  uuid := gen_random_uuid();
    v_n      int;
begin
    -- ── Fixtures ──────────────────────────────────────────────────────────────
    insert into auth.users (id) values (v_vendor), (v_owner), (v_other);
    insert into public.profiles (id, display_name) values
        (v_vendor, 'Vendor'), (v_owner, 'Owner'), (v_other, 'Other');
    insert into public.vendor_profiles (profile_id, is_listed) values (v_vendor, true);

    -- A booking: vendor claimed an event dated 2026-08-15.
    insert into public.events (id, owner_id, title, date, status)
        values (v_event, v_owner, 'Summer Gala', timestamptz '2026-08-15 18:00:00+00', 'planning');
    insert into public.event_vendors (event_id, profile_id, display_name, role, accepted_at)
        values (v_event, v_vendor, 'Vendor', 'dj', now());

    -- A manual busy day.
    insert into public.vendor_busy_dates (profile_id, busy_date, note)
        values (v_vendor, date '2026-08-20', 'Out of town');

    -- ── get_my_calendar returns manual + booked in range ─────────────────────
    perform set_config('request.jwt.claims', json_build_object('sub', v_vendor::text)::text, true);

    select count(*) into v_n
      from public.get_my_calendar(date '2026-08-01', date '2026-08-31');
    if v_n <> 2 then
        raise exception 'get_my_calendar expected 2 rows, got %', v_n;
    end if;

    if not exists (
        select 1 from public.get_my_calendar(date '2026-08-01', date '2026-08-31')
        where busy_date = date '2026-08-20' and kind = 'manual'
    ) then
        raise exception 'manual busy day 2026-08-20 missing';
    end if;

    if not exists (
        select 1 from public.get_my_calendar(date '2026-08-01', date '2026-08-31')
        where busy_date = date '2026-08-15' and kind = 'booked' and event_title = 'Summer Gala'
    ) then
        raise exception 'booked day 2026-08-15 (Summer Gala) missing';
    end if;
    raise notice 'get_my_calendar manual + booked OK';

    -- Range bounds: a window with neither day returns nothing.
    select count(*) into v_n
      from public.get_my_calendar(date '2026-09-01', date '2026-09-30');
    if v_n <> 0 then
        raise exception 'out-of-range window expected 0 rows, got %', v_n;
    end if;
    raise notice 'range filtering OK';

    -- ── RLS: manual busy dates are PRIVATE to the owner ──────────────────────
    execute 'set local role authenticated';

    perform set_config('request.jwt.claims', json_build_object('sub', v_vendor::text)::text, true);
    select count(*) into v_n from public.vendor_busy_dates;
    if v_n <> 1 then
        raise exception 'owner should see their own busy date, saw %', v_n;
    end if;

    perform set_config('request.jwt.claims', json_build_object('sub', v_other::text)::text, true);
    select count(*) into v_n from public.vendor_busy_dates;
    if v_n <> 0 then
        raise exception 'RLS LEAK: another user saw % private busy rows', v_n;
    end if;

    execute 'reset role';
    raise notice 'owner-only RLS OK (private to vendor)';

    raise notice 'ALL AVAILABILITY TESTS PASSED';
end;
$$;

rollback;
