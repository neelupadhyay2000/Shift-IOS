-- Marketplace Launch (E24 Task 1): launch-announcement idempotency stamp.
--
-- The one-shot `marketplace-launch-notify` Edge Function fans out "The Shift
-- Marketplace is live" to marketplace_waitlist members in two staggered waves
-- (vendor-role first so supply seeds before planner discovery traffic). This
-- column is what makes the fan-out one-shot and the stagger safe:
--   - a member is targeted only while launch_notified_at IS NULL;
--   - the function stamps it after a successful APNs send;
--   - re-running a wave (crash, partial APNs outage, curl retried) skips
--     everyone already stamped instead of double-pushing them;
--   - 'both'-role members are stamped by the vendor wave, so the later
--     planner wave (interest_role = 'planner') can never hit them twice.
--
-- Written only by the Edge Function (service role — bypasses RLS); the
-- self-only RLS policy is untouched, so members can still read/update their
-- own row but gain nothing writable here that matters.

alter table public.marketplace_waitlist
    add column launch_notified_at timestamptz;

comment on column public.marketplace_waitlist.launch_notified_at
    is 'When the one-shot marketplace-launch push was sent to this member '
       '(marketplace-launch-notify Edge Function, service role). NULL = not yet '
       'notified — the function only targets NULL rows, making waves re-runnable.';

-- Wave query: live, un-notified members of a role set. Partial index keeps the
-- fan-out scan cheap even as the waitlist grows.
create index marketplace_waitlist_launch_wave_idx
    on public.marketplace_waitlist (interest_role)
    where launch_notified_at is null and deleted_at is null;
