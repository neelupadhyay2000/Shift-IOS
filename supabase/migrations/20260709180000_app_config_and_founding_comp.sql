-- Growth: remote-configurable free-tier limits + a founding-cohort comp.
--
-- WHY
-- Two problems, one migration:
--
-- 1. `FreeTier` was a compile-time constant in SHIFTKit, so widening or tightening
--    the free plan cost an App Store release each way. That made the limits
--    effectively permanent, which is the wrong property for a number you want to
--    tune while finding product-market fit. `app_config` makes them a data
--    decision, flippable in seconds from the dashboard.
--
-- 2. The paywall throttles the marketplace flywheel while there is no liquidity to
--    monetize. Rather than delete the paywall (a near one-way door — re-introducing
--    one to a base trained on free is the most churn-inducing move in consumer
--    software), we comp the founding cohort. The plumbing already exists:
--    `profiles.comped_until` → `SupabaseAuthService.currentProfile` didSet →
--    `SubscriptionManager.compedUntil` → `isProUser`. Nothing else changes; the
--    paywall, the products, and the price anchor all survive intact.
--
-- `comped_until` is deliberately NOT in the `authenticated` column grant (see
-- 20260612130000_profiles_comped_until.sql), so a client can never grant itself
-- Pro. The trigger below is SECURITY DEFINER and is the only automatic writer.

-- ─────────────────────────────────────────────────────────────────────────────
-- app_config — small key/value store for values we want to change without a ship.
-- Read-only to clients; writes are service-role (dashboard SQL) only.
-- ─────────────────────────────────────────────────────────────────────────────
create table public.app_config (
    key         text primary key,
    value       jsonb not null,
    updated_at  timestamptz not null default now()
);

comment on table public.app_config
    is 'Remote app configuration, read by every signed-in client at launch. '
       'Client-readable, service-role-writable only. Keys: free_tier, founding.';

alter table public.app_config enable row level security;

-- Any signed-in user may read config. There is deliberately no insert/update/
-- delete policy: only the service role (dashboard) writes here.
create policy "app_config_authenticated_select" on public.app_config
    for select
    to authenticated
    using (true);

revoke all on public.app_config from anon;

create trigger set_updated_at
    before update on public.app_config
    for each row execute function public.set_updated_at();

-- The widened free plan. Keys match `FreeTierLimits` on iOS exactly (camelCase),
-- so the client decodes this jsonb straight into the struct.
--
-- Previously: 1 active event, 15 blocks, 2 templates. One event is below the
-- threshold where a planner forms a habit, and it silently dead-ended community
-- templates (apply → create event → blocked) and service requests (the composer
-- makes you pick one of *your* events).
insert into public.app_config (key, value) values
    ('free_tier', '{"maxActiveEvents": 5, "maxBlocksPerEvent": 40, "maxTemplates": 10}'::jsonb)
on conflict (key) do nothing;

-- The founding window. Every account created before `signup_before` is comped Pro
-- for `comp_months`. Move the date to extend the window, or set it to a past
-- instant to close it — no app release required either way.
insert into public.app_config (key, value) values
    ('founding', '{"signup_before": "2027-01-01T00:00:00Z", "comp_months": 12}'::jsonb)
on conflict (key) do nothing;

-- ─────────────────────────────────────────────────────────────────────────────
-- Founding comp — stamped server-side on profile creation.
--
-- BEFORE INSERT so the value lands in the same row write (no second UPDATE, no
-- window where a founding user reads as free). SECURITY DEFINER so it can read
-- app_config regardless of the caller's grants, and because `comped_until` is
-- outside the client's column grant.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.stamp_founding_comp()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_config       jsonb;
    v_signup_before timestamptz;
    v_months       integer;
begin
    -- Never overwrite an explicit comp (e.g. one granted by comp_account()).
    if new.comped_until is not null then
        return new;
    end if;

    select value into v_config from public.app_config where key = 'founding';
    if v_config is null then
        return new;
    end if;

    v_signup_before := (v_config ->> 'signup_before')::timestamptz;
    v_months        := coalesce((v_config ->> 'comp_months')::integer, 0);

    if v_signup_before is null or v_months <= 0 then
        return new;
    end if;

    if now() < v_signup_before then
        new.comped_until := now() + make_interval(months => v_months);
    end if;

    return new;
end;
$$;

comment on function public.stamp_founding_comp()
    is 'BEFORE INSERT on profiles: grants the founding cohort a complimentary Pro '
       'window (app_config.founding). Never overwrites an existing comp. The only '
       'automatic writer of profiles.comped_until.';

create trigger profiles_stamp_founding_comp
    before insert on public.profiles
    for each row execute function public.stamp_founding_comp();

-- ─────────────────────────────────────────────────────────────────────────────
-- Backfill — everyone who already signed up is, by definition, founding.
-- Only touches accounts with no live comp, so a hand-granted comp is preserved.
-- ─────────────────────────────────────────────────────────────────────────────
do $$
declare
    v_config        jsonb;
    v_signup_before timestamptz;
    v_months        integer;
    v_count         integer;
begin
    select value into v_config from public.app_config where key = 'founding';
    v_signup_before := (v_config ->> 'signup_before')::timestamptz;
    v_months        := coalesce((v_config ->> 'comp_months')::integer, 0);

    if v_signup_before is null or v_months <= 0 then
        raise notice 'founding backfill skipped: config missing or disabled';
        return;
    end if;

    update public.profiles
       set comped_until = now() + make_interval(months => v_months)
     where deleted_at is null
       and created_at < v_signup_before
       and (comped_until is null or comped_until < now());

    get diagnostics v_count = row_count;
    raise notice 'founding backfill: comped % existing account(s)', v_count;
end;
$$;
