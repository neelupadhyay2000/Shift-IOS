-- Verification for E19: profiles.onboarded gate.
-- Transactional (ROLLBACK). Run:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/profiles_onboarded_test.sql
-- Clean run ends with "ALL ONBOARDED TESTS PASSED".

begin;

set local client_min_messages = notice;

do $$
declare
    v_new uuid := gen_random_uuid();
    v_onboarded boolean;
begin
    insert into auth.users (id) values (v_new);

    -- A freshly-inserted profile (mirrors performProfileUpsert: posts id only) is
    -- NOT onboarded by default → the app will force the setup UI.
    insert into public.profiles (id, display_name) values (v_new, '');
    select onboarded into v_onboarded from public.profiles where id = v_new;
    if v_onboarded then raise exception 'new profile should default onboarded=false'; end if;
    raise notice 'new profile defaults onboarded=false OK';

    -- Completing onboarding flips it to true.
    update public.profiles set onboarded = true, display_name = 'Neel', default_role = 'planner'
        where id = v_new;
    select onboarded into v_onboarded from public.profiles where id = v_new;
    if not v_onboarded then raise exception 'onboarded should be true after completion'; end if;
    raise notice 'onboarding completion sets onboarded=true OK';

    raise notice 'ALL ONBOARDED TESTS PASSED';
end;
$$;

rollback;
