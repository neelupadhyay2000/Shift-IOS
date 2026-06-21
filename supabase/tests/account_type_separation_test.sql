-- Verification for E21: account_type backfill + vendor purge semantics.
-- Transactional (ROLLBACK). Clean run ends "ALL ACCOUNT-TYPE TESTS PASSED".

begin;
set local client_min_messages = notice;

do $$
declare
    v_planner uuid := gen_random_uuid();
    v_vendor  uuid := gen_random_uuid();
    v_expired uuid := gen_random_uuid();
    v_grace   uuid := gen_random_uuid();
    v_type    text;
    v_exists   boolean;
begin
    insert into auth.users (id) values (v_planner), (v_vendor), (v_expired), (v_grace);
    insert into public.profiles (id, display_name) values
        (v_planner,'P'),(v_vendor,'V'),(v_expired,'E'),(v_grace,'G');
    insert into public.vendor_profiles (profile_id, is_listed) values
        (v_vendor,true),(v_expired,true),(v_grace,true);

    -- Backfill rule (same expression as the migration).
    update public.profiles p set account_type = case
            when exists (select 1 from public.vendor_profiles vp where vp.profile_id = p.id and vp.deleted_at is null)
            then 'vendor' else 'planner' end
        where p.id in (v_planner, v_vendor, v_expired, v_grace);

    select account_type into v_type from public.profiles where id = v_planner;
    if v_type <> 'planner' then raise exception 'planner backfill wrong: %', v_type; end if;
    select account_type into v_type from public.profiles where id = v_vendor;
    if v_type <> 'vendor' then raise exception 'vendor backfill wrong: %', v_type; end if;
    raise notice 'account_type backfill OK';

    -- account_type CHECK rejects bad values.
    begin
        update public.profiles set account_type = 'both' where id = v_planner;
        raise exception 'CHECK should have rejected account_type=both';
    exception when check_violation then null;
    end;
    raise notice 'account_type CHECK OK';

    -- Switch-to-planner semantics: hide + schedule purge.
    update public.vendor_profiles set is_listed = false, purge_after = now() + interval '30 days'
        where profile_id = v_grace;
    update public.vendor_profiles set is_listed = false, purge_after = now() - interval '1 day'
        where profile_id = v_expired;

    -- Purge (same statement as the cron) deletes only past-grace rows.
    delete from public.vendor_profiles where purge_after is not null and purge_after < now();

    select exists (select 1 from public.vendor_profiles where profile_id = v_expired) into v_exists;
    if v_exists then raise exception 'expired vendor profile should be purged'; end if;
    select exists (select 1 from public.vendor_profiles where profile_id = v_grace) into v_exists;
    if not v_exists then raise exception 'in-grace vendor profile must NOT be purged'; end if;
    select exists (select 1 from public.vendor_profiles where profile_id = v_vendor) into v_exists;
    if not v_exists then raise exception 'active vendor profile must NOT be purged'; end if;
    raise notice 'purge deletes only past-grace rows OK';

    -- cron job is registered.
    select exists (select 1 from cron.job where jobname = 'purge-expired-vendor-profiles') into v_exists;
    if not v_exists then raise exception 'purge cron job not scheduled'; end if;
    raise notice 'purge cron scheduled OK';

    raise notice 'ALL ACCOUNT-TYPE TESTS PASSED';
end;
$$;

rollback;
