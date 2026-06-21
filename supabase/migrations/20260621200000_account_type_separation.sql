-- Planner/Vendor account separation (E21)
--
-- An account is EITHER a planner OR a vendor — never both. account_type is the
-- authoritative switch the app gates on (planners request vendors; vendors get
-- requested + manage a listing). Users can switch, losing the other side's
-- features. Switching vendor→planner hides the vendor listing immediately and
-- schedules it for permanent deletion after a 30-day grace (vendor_profiles
-- .purge_after); switching back within the window cancels the deletion.

-- ─────────────────────────────────────────────────────────────────────────────
-- profiles.account_type
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.profiles
    add column account_type text not null default 'planner'
        check (account_type in ('planner', 'vendor'));

comment on column public.profiles.account_type is
    'Exclusive account persona (E21): planner (requests vendors) or vendor '
    '(receives requests + manages a listing). The app hard-gates marketplace '
    'features on this. Set at onboarding; switchable in Settings.';

-- Backfill: anyone with a live vendor listing is a vendor; everyone else planner.
update public.profiles p
set account_type = case
        when exists (
            select 1 from public.vendor_profiles vp
            where vp.profile_id = p.id and vp.deleted_at is null
        ) then 'vendor'
        else 'planner'
    end;

-- Column allow-list (profiles restricts grants — see comped_until migration).
grant insert (account_type) on table public.profiles to authenticated;
grant update (account_type) on table public.profiles to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- vendor_profiles.purge_after — 30-day deletion grace after switching to planner
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.vendor_profiles
    add column purge_after timestamptz;

comment on column public.vendor_profiles.purge_after is
    'When set, this hidden vendor profile is permanently deleted after this '
    'instant (30-day grace after switching to a planner account). Cleared when '
    'the user switches back to vendor. Reaped by the purge-expired-vendor-profiles '
    'cron. vendor_profiles has no column allow-list, so the owner writes it via RLS.';

-- ─────────────────────────────────────────────────────────────────────────────
-- Daily purge: hard-delete vendor profiles past their grace. The FK cascades
-- (portfolio_items, vendor_reviews, vendor_busy_dates) clean up dependent rows —
-- a true permanent deletion. Runs as the job owner (postgres), bypassing RLS.
-- ─────────────────────────────────────────────────────────────────────────────
create extension if not exists pg_cron;

select cron.schedule(
    'purge-expired-vendor-profiles',
    '0 3 * * *',
    $$delete from public.vendor_profiles where purge_after is not null and purge_after < now();$$
);
