-- Forced onboarding (E19) — corrective backfill
--
-- The initial migration (20260621180000) backfilled EVERY existing profile to
-- onboarded = true. We actually want existing users who never created a real
-- profile to be prompted on next launch. Re-derive onboarded authoritatively:
-- a user counts as already-onboarded only if they have a real profile signal —
-- a display name, a business name, or a marketplace vendor row. Everyone else
-- (e.g. an email-OTP account that auto-created a bare profiles row with an empty
-- display_name) flips to false and goes through profile creation next time.
--
-- This only touches rows that exist now; new signups keep the column default
-- (false) and onboard normally.

update public.profiles p
set onboarded = (
        nullif(btrim(coalesce(p.display_name, '')), '') is not null
     or nullif(btrim(coalesce(p.business_name, '')), '') is not null
     or exists (
            select 1
            from public.vendor_profiles vp
            where vp.profile_id = p.id
              and vp.deleted_at is null
        )
    );
