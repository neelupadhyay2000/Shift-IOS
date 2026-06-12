-- Complimentary Pro for specific accounts (early field testers, press).
--
-- profiles.comped_until: a future instant grants the account Pro in the app
-- without a StoreKit purchase; null or a past instant grants nothing. The app
-- reads it from the signed-in profile and ORs it into the entitlement check.
--
-- Column-level grants are the enforcement: the profiles_self_all RLS policy
-- lets a user INSERT/UPDATE their own row, so without these revokes a user
-- could comp themselves. The authenticated role keeps every column EXCEPT
-- comped_until; only the service role (dashboard SQL / comp_account()) may
-- write it. The iOS ProfileDTO also never encodes the column, so a returning
-- user's profile upsert cannot clear an existing grant.

alter table public.profiles add column comped_until timestamptz;

comment on column public.profiles.comped_until is
    'Complimentary Pro until this instant; null = none. Service-role writable only '
    '(excluded from the authenticated role''s column grants).';

revoke insert, update on table public.profiles from authenticated;

grant insert (id, display_name, phone, email, default_role,
              avatar_url, business_name, bio, portfolio_url,
              created_at, updated_at, deleted_at)
    on table public.profiles to authenticated;

-- `id` must be update-grantable: PostgREST upserts run
-- INSERT ... ON CONFLICT DO UPDATE SET <every posted column>, including id.
-- RLS (profiles_self_all WITH CHECK) still pins the row to auth.uid(), so the
-- value can never actually change to another user's id.
grant update (id, display_name, phone, email, default_role,
              avatar_url, business_name, bio, portfolio_url,
              created_at, updated_at, deleted_at)
    on table public.profiles to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- comp_account(email, months) — operator convenience for the dashboard SQL
-- editor:  select comp_account('tester@example.com', 3);
-- Months are counted from now (not extended), so re-running resets the window.
-- Pass 0 to revoke a comp immediately. Execute is service-side only.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.comp_account(target_email text, months integer)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_id uuid;
    new_until timestamptz;
begin
    select id into target_id
    from auth.users
    where lower(email) = lower(trim(target_email));

    if target_id is null then
        raise exception 'no auth user with email %', target_email;
    end if;

    update public.profiles
    set comped_until = now() + make_interval(months => months)
    where id = target_id
    returning comped_until into new_until;

    if new_until is null then
        raise exception 'no profiles row for % — has the user signed in once?', target_email;
    end if;

    return new_until;
end;
$$;

revoke all on function public.comp_account(text, integer) from public, anon, authenticated;
