-- Verification for E18 Story 2: search_vendors p_on_date availability filter.
-- Self-contained, transactional (ROLLBACK). All probe vendors share the unique
-- search_name 'e18probe' so assertions are isolated from real directory data.
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/search_vendors_on_date_test.sql
-- Clean run ends with "ALL SEARCH-ON-DATE TESTS PASSED".

begin;

set local client_min_messages = notice;

do $$
declare
    v_caller uuid := gen_random_uuid();   -- the searching planner
    v_busy   uuid := gen_random_uuid();   -- manually busy on 08-20
    v_booked uuid := gen_random_uuid();   -- booked on an event dated 08-15
    v_free   uuid := gen_random_uuid();   -- always available
    v_owner  uuid := gen_random_uuid();   -- planner who owns the booking event
    v_event  uuid := gen_random_uuid();
    v_total  int;
    v_busy_on20   boolean; v_booked_on20 boolean; v_free_on20 boolean;
    v_busy_on15   boolean; v_booked_on15 boolean; v_free_on15 boolean;
begin
    -- ── Fixtures ──────────────────────────────────────────────────────────────
    insert into auth.users (id) values (v_busy), (v_booked), (v_free), (v_owner);
    insert into public.profiles (id, display_name) values
        (v_busy, 'Busy'), (v_booked, 'Booked'), (v_free, 'Free'), (v_owner, 'Owner');
    -- Shared probe token in search_name so only these three match the query.
    insert into public.vendor_profiles (profile_id, is_listed, search_name) values
        (v_busy, true, 'e18probe'), (v_booked, true, 'e18probe'), (v_free, true, 'e18probe');

    insert into public.vendor_busy_dates (profile_id, busy_date) values (v_busy, date '2026-08-20');

    insert into public.events (id, owner_id, title, date, status)
        values (v_event, v_owner, 'Booked Gala', timestamptz '2026-08-15 18:00:00+00', 'planning');
    insert into public.event_vendors (event_id, profile_id, display_name, role, accepted_at)
        values (v_event, v_booked, 'Booked', 'dj', now());

    perform set_config('request.jwt.claims', json_build_object('sub', v_caller::text)::text, true);

    -- ── No date → E10 behavior: all three returned ───────────────────────────
    select count(*) into v_total from public.search_vendors(p_query => 'e18probe', p_limit => 50);
    if v_total <> 3 then
        raise exception 'no-date search expected 3 probe vendors, got %', v_total;
    end if;
    raise notice 'no-date search returns all 3 OK';

    -- ── Presence per (vendor, date) ──────────────────────────────────────────
    select
        exists (select 1 from public.search_vendors(p_query=>'e18probe',p_limit=>50,p_on_date=>date '2026-08-20') where profile_id=v_busy),
        exists (select 1 from public.search_vendors(p_query=>'e18probe',p_limit=>50,p_on_date=>date '2026-08-20') where profile_id=v_booked),
        exists (select 1 from public.search_vendors(p_query=>'e18probe',p_limit=>50,p_on_date=>date '2026-08-20') where profile_id=v_free),
        exists (select 1 from public.search_vendors(p_query=>'e18probe',p_limit=>50,p_on_date=>date '2026-08-15') where profile_id=v_busy),
        exists (select 1 from public.search_vendors(p_query=>'e18probe',p_limit=>50,p_on_date=>date '2026-08-15') where profile_id=v_booked),
        exists (select 1 from public.search_vendors(p_query=>'e18probe',p_limit=>50,p_on_date=>date '2026-08-15') where profile_id=v_free)
    into v_busy_on20, v_booked_on20, v_free_on20, v_busy_on15, v_booked_on15, v_free_on15;

    -- 08-20: only the manually-busy vendor is excluded.
    if v_busy_on20 then raise exception 'manually-busy vendor not excluded on 2026-08-20'; end if;
    if not v_booked_on20 or not v_free_on20 then raise exception 'non-busy vendors wrongly excluded on 2026-08-20'; end if;
    raise notice 'manual busy exclusion OK';

    -- 08-15: only the booked vendor is excluded.
    if v_booked_on15 then raise exception 'booked vendor not excluded on 2026-08-15'; end if;
    if not v_busy_on15 or not v_free_on15 then raise exception 'unbooked vendors wrongly excluded on 2026-08-15'; end if;
    raise notice 'booked exclusion OK';

    -- The free vendor is never excluded.
    if not v_free_on20 or not v_free_on15 then raise exception 'free vendor wrongly excluded'; end if;
    raise notice 'free vendor always present OK';

    raise notice 'ALL SEARCH-ON-DATE TESTS PASSED';
end;
$$;

rollback;
