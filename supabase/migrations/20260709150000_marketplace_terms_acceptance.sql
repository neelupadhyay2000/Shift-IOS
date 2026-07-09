-- Marketplace Launch (E24 Task 3) — record Terms acceptance at vendor opt-in.
--
-- Apple Guideline 1.2 requires that users who publish UGC affirmatively agree to
-- terms with a no-tolerance policy for objectionable content. Vendors are the
-- publishing side of the marketplace (profiles, portfolio photos), so acceptance
-- is recorded at the two — and only two — vendor opt-in choke points:
--   * OnboardingProviding.completeVendor(_:)  (new account chooses vendor)
--   * OnboardingProviding.switchToVendor()    (planner → vendor)
--
-- Tamper-evident by construction: the columns are NOT in the `authenticated`
-- column-update grant (see 20260612130000_profiles_comped_until.sql), so a client
-- cannot PATCH them. The only write path is the SECURITY DEFINER RPC below, which
-- stamps `now()` server-side for `auth.uid()` — a client can never backdate or
-- forge an acceptance, and the recorded timestamp is the server's.

alter table public.profiles
    add column marketplace_terms_accepted_at timestamptz,
    add column marketplace_terms_version     text;

comment on column public.profiles.marketplace_terms_accepted_at
    is 'Server timestamp of the user''s affirmative acceptance of the marketplace '
       'Terms (Guideline 1.2). Written ONLY by accept_marketplace_terms(); not in '
       'the authenticated column-update grant, so it cannot be forged client-side.';
comment on column public.profiles.marketplace_terms_version
    is 'The Terms version string the user accepted (MarketplaceTerms.currentVersion '
       'on iOS). Lets a future Terms revision re-prompt only stale acceptors.';

-- Moderation/compliance lookup: "show me every vendor and when they accepted".
create index profiles_marketplace_terms_idx
    on public.profiles (marketplace_terms_accepted_at)
    where marketplace_terms_accepted_at is not null;

-- ─────────────────────────────────────────────────────────────────────────────
-- accept_marketplace_terms() — the ONLY write path for the acceptance stamp.
--
-- Idempotent per version: re-accepting the same version refreshes nothing and
-- returns the original timestamp, so a retried opt-in can't rewrite history.
-- Accepting a NEW version overwrites (the latest acceptance is what governs).
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.accept_marketplace_terms(p_version text)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_uid      uuid := auth.uid();
    v_existing timestamptz;
    v_version  text;
begin
    if v_uid is null then
        raise exception 'accept_marketplace_terms: not authenticated'
            using errcode = '28000';
    end if;
    if coalesce(btrim(p_version), '') = '' then
        raise exception 'accept_marketplace_terms: version required'
            using errcode = '22023';
    end if;

    select marketplace_terms_accepted_at, marketplace_terms_version
      into v_existing, v_version
      from public.profiles
     where id = v_uid;

    -- Same version already on file → keep the original timestamp.
    if v_existing is not null and v_version is not distinct from p_version then
        return v_existing;
    end if;

    update public.profiles
       set marketplace_terms_accepted_at = now(),
           marketplace_terms_version     = p_version
     where id = v_uid
    returning marketplace_terms_accepted_at into v_existing;

    return v_existing;
end;
$$;

comment on function public.accept_marketplace_terms(text)
    is 'Stamps the caller''s affirmative acceptance of the marketplace Terms '
       '(Guideline 1.2) with a server timestamp. Idempotent per version. The only '
       'write path for profiles.marketplace_terms_* — SECURITY DEFINER, '
       'authenticated-only, cannot be forged or backdated by a client.';

revoke all on function public.accept_marketplace_terms(text) from public, anon;
grant execute on function public.accept_marketplace_terms(text) to authenticated;
