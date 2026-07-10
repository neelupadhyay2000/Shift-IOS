-- comp_account: accept a phone number as well as an email.
--
-- WHY
-- Phone OTP sign-in went live (2026-07-09), so an account can now exist that has
-- no email yet: a phone signup is only asked for one *after* onboarding, by
-- `CompleteProfileView`. `comp_account(target_email, months)` looked the user up
-- by `auth.users.email`, so exactly those accounts — a phone user mid-onboarding,
-- or one who bailed before adding an email — were un-comp-able by hand.
--
-- (The founding-cohort trigger in 20260709180000 is email-independent and already
-- covers them automatically. This is for the operator path: press, testers, support.)
--
-- HOW
-- One function, two identifier kinds, disambiguated by '@':
--     select comp_account('tester@example.com', 3);
--     select comp_account('+1 (647) 555-1234', 3);
--     select comp_account('16475551234', 3);
--
-- GoTrue stores `auth.users.phone` in E.164 **without** the leading '+'
-- (e.g. `16475551234`), while operators paste all sorts of formatting. Both sides
-- are normalised to digits before comparing, so any of the forms above resolve to
-- the same user.
--
-- Semantics are unchanged: months are counted from now (not extended), so
-- re-running resets the window, and `months => 0` revokes a comp immediately
-- (`comped_until = now()` and `isCompActive` requires strictly greater than now).
--
-- `CREATE OR REPLACE` cannot rename an input parameter, so the old signature is
-- dropped first. It is a service-role-only operator function — nothing in the app
-- calls it, so there is no window to worry about.

drop function if exists public.comp_account(text, integer);

create or replace function public.comp_account(target text, months integer)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_target    text := btrim(coalesce(target, ''));
    v_digits    text;
    v_target_id uuid;
    v_new_until timestamptz;
begin
    if v_target = '' then
        raise exception 'comp_account: target (email or phone) is required'
            using errcode = '22023';
    end if;

    if position('@' in v_target) > 0 then
        -- Email path (unchanged).
        select id into v_target_id
        from auth.users
        where lower(email) = lower(v_target);

        if v_target_id is null then
            raise exception 'no auth user with email %', v_target
                using errcode = 'P0002';
        end if;
    else
        -- Phone path. Compare digits-only on both sides so '+1 (647) 555-1234',
        -- '+16475551234' and '16475551234' all resolve to the same account.
        v_digits := regexp_replace(v_target, '\D', '', 'g');

        if length(v_digits) < 7 then
            raise exception
                'comp_account: % is neither an email address nor a usable phone number', v_target
                using errcode = '22023';
        end if;

        select id into v_target_id
        from auth.users
        where regexp_replace(coalesce(phone, ''), '\D', '', 'g') = v_digits;

        if v_target_id is null then
            raise exception 'no auth user with phone % (normalised: %)', v_target, v_digits
                using errcode = 'P0002';
        end if;
    end if;

    update public.profiles
       set comped_until = now() + make_interval(months => months)
     where id = v_target_id
    returning comped_until into v_new_until;

    if v_new_until is null then
        raise exception 'no profiles row for % — has the user signed in once?', v_target
            using errcode = 'P0002';
    end if;

    return v_new_until;
end;
$$;

comment on function public.comp_account(text, integer)
    is 'Operator convenience: grant (or revoke, with months => 0) a complimentary '
       'Pro window. `target` is an email address, or a phone number in any format — '
       'phone lookups normalise both sides to digits, since GoTrue stores '
       'auth.users.phone in E.164 without the leading +. Months count from now, so '
       're-running resets rather than extends. SECURITY DEFINER, service-role only.';

-- Service-side only; never reachable from the app.
revoke all on function public.comp_account(text, integer) from public, anon, authenticated;
