-- Forced profile onboarding (E19) — profiles.onboarded gate
--
-- New flow: after email OTP, a user must create a profile (planner or vendor)
-- before reaching the app — the Instagram/Hinge pattern. `onboarded` is the gate:
-- the app blocks on the profile-creation UI until it is true.
--
-- Existing users are backfilled to true so this never blocks anyone already in
-- the app. New rows default false (the profiles row is auto-inserted on first
-- sign-in by performProfileUpsert, which doesn't post onboarded → default holds);
-- the onboarding flow flips it to true once the profile is created.

alter table public.profiles
    add column onboarded boolean not null default false;

comment on column public.profiles.onboarded is
    'True once the user completed profile creation (planner or vendor). The app '
    'forces the profile-setup UI while false. Backfilled true for pre-E19 users.';

-- One-time backfill: everyone who already exists has effectively onboarded.
update public.profiles set onboarded = true;

-- Column-level grants (profiles uses an allow-list; see comped_until migration):
-- the user must be able to write their own onboarded flag.
grant insert (onboarded) on table public.profiles to authenticated;
grant update (onboarded) on table public.profiles to authenticated;
