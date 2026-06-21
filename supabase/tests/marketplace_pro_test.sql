-- Verification for E22: saved_vendors RLS, get_saved_vendors, search_vendors p_sort.
-- Transactional (ROLLBACK). Clean run ends "ALL MARKETPLACE-PRO TESTS PASSED".

begin;
set local client_min_messages = notice;

do $$
declare
    v_planner uuid := gen_random_uuid();
    v_a uuid := gen_random_uuid();   -- high rating, fewer events
    v_b uuid := gen_random_uuid();   -- lower rating, more events
    v_n int;
    v_first uuid;
begin
    insert into auth.users (id) values (v_planner), (v_a), (v_b);
    insert into public.profiles (id, display_name) values (v_planner,'P'),(v_a,'A'),(v_b,'B');
    insert into public.vendor_profiles (profile_id, is_listed, search_name, rating_avg, rating_count, events_completed_count)
        values (v_a, true, 'e22probe', 4.90, 10, 3),
               (v_b, true, 'e22probe', 4.10, 5, 20);

    perform set_config('request.jwt.claims', json_build_object('sub', v_planner::text)::text, true);

    -- p_sort=rating → A first; p_sort=booked → B first.
    select profile_id into v_first from public.search_vendors(p_query=>'e22probe', p_sort=>'rating') limit 1;
    if v_first <> v_a then raise exception 'sort rating expected A first'; end if;
    select profile_id into v_first from public.search_vendors(p_query=>'e22probe', p_sort=>'booked') limit 1;
    if v_first <> v_b then raise exception 'sort booked expected B first'; end if;
    raise notice 'search_vendors p_sort OK';

    -- Save vendor A → appears in get_saved_vendors; B does not.
    insert into public.saved_vendors (planner_id, vendor_profile_id) values (v_planner, v_a);
    select count(*) into v_n from public.get_saved_vendors();
    if v_n <> 1 then raise exception 'get_saved_vendors expected 1, got %', v_n; end if;
    select profile_id into v_first from public.get_saved_vendors() limit 1;
    if v_first <> v_a then raise exception 'saved vendor should be A'; end if;
    raise notice 'get_saved_vendors OK';

    -- RLS: another user can't see this planner's saved rows.
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', v_b::text)::text, true);
    select count(*) into v_n from public.saved_vendors;
    if v_n <> 0 then raise exception 'RLS LEAK: saw % saved rows', v_n; end if;
    execute 'reset role';
    raise notice 'saved_vendors owner-only RLS OK';

    raise notice 'ALL MARKETPLACE-PRO TESTS PASSED';
end;
$$;

rollback;
