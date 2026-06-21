-- Verification for E19 corrective backfill: existing users without a real profile
-- are flipped to onboarded=false (prompted), those with one stay true.
-- Transactional (ROLLBACK). Clean run ends "ALL BACKFILL TESTS PASSED".

begin;

set local client_min_messages = notice;

do $$
declare
    v_bare    uuid := gen_random_uuid();   -- email-only, empty display_name → prompt
    v_named   uuid := gen_random_uuid();   -- has a display name → skip
    v_vendor  uuid := gen_random_uuid();   -- has a vendor_profiles row → skip
    v_biz     uuid := gen_random_uuid();   -- has a business name → skip
    v_onb     boolean;
begin
    insert into auth.users (id) values (v_bare), (v_named), (v_vendor), (v_biz);

    -- All start onboarded=true (simulating the first migration's blanket backfill).
    insert into public.profiles (id, display_name, business_name, onboarded) values
        (v_bare,   '',        null,            true),
        (v_named,  'Neel',    null,            true),
        (v_vendor, '',        null,            true),
        (v_biz,    '',        'Golden Hour',   true);
    insert into public.vendor_profiles (profile_id, is_listed) values (v_vendor, true);

    -- Re-run the corrective UPDATE (same expression as the migration).
    update public.profiles p
    set onboarded = (
            nullif(btrim(coalesce(p.display_name, '')), '') is not null
         or nullif(btrim(coalesce(p.business_name, '')), '') is not null
         or exists (select 1 from public.vendor_profiles vp where vp.profile_id = p.id and vp.deleted_at is null)
        )
    where p.id in (v_bare, v_named, v_vendor, v_biz);

    select onboarded into v_onb from public.profiles where id = v_bare;
    if v_onb then raise exception 'bare profile should be prompted (onboarded=false)'; end if;

    select onboarded into v_onb from public.profiles where id = v_named;
    if not v_onb then raise exception 'named profile should skip (onboarded=true)'; end if;

    select onboarded into v_onb from public.profiles where id = v_vendor;
    if not v_onb then raise exception 'vendor profile should skip (onboarded=true)'; end if;

    select onboarded into v_onb from public.profiles where id = v_biz;
    if not v_onb then raise exception 'business-name profile should skip (onboarded=true)'; end if;

    raise notice 'bare→prompt, named/vendor/business→skip OK';
    raise notice 'ALL BACKFILL TESTS PASSED';
end;
$$;

rollback;
