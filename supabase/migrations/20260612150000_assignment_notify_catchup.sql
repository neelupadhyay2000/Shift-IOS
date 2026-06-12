-- Close the two gaps that made block-assignment pushes effectively silent:
--
-- 1. Pre-claim assignments were never notified. The INSERT trigger skips
--    unclaimed vendors (profile_id null) by design — but in the real planner
--    workflow blocks are assigned while building the timeline, BEFORE the
--    vendor claims the invite, so most assignments fired into the skip path
--    and there was no catch-up when the vendor finally claimed. New trigger:
--    when claim_invite links profile_id (null → set), summarize the vendor's
--    live assignments in one push ("You've been added to N blocks.").
--
-- 2. Re-assignment after unassign was never notified: the row already exists
--    soft-deleted, so re-assignment arrives as UPDATE (deleted_at → null),
--    which the INSERT-only trigger ignored. New trigger fires the existing
--    notify function on that specific resurrection transition.

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Re-assignment: resurrecting a soft-deleted block_vendors row notifies.
--    notify_block_assignment() reads only NEW, so it serves UPDATE unchanged.
-- ─────────────────────────────────────────────────────────────────────────────
drop trigger if exists trg_notify_block_reassignment on public.block_vendors;
create trigger trg_notify_block_reassignment
    after update of deleted_at on public.block_vendors
    for each row
    when (old.deleted_at is not null and new.deleted_at is null)
    execute function public.notify_block_assignment();

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Claim-time catch-up: when a vendor claims (profile_id null → set),
--    summarize their pre-claim block assignments in a single push.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.notify_claimed_assignments()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_project_url text;
    v_service_key text;
    v_count       integer;
    v_first_title text;
begin
    select count(*), min(b.title)
        into v_count, v_first_title
        from public.block_vendors bv
        join public.blocks b on b.id = bv.block_id
        where bv.event_vendor_id = new.id
          and bv.deleted_at is null;

    if coalesce(v_count, 0) = 0 then
        return new;
    end if;

    select decrypted_secret into v_project_url
        from vault.decrypted_secrets where name = 'project_url';
    select decrypted_secret into v_service_key
        from vault.decrypted_secrets where name = 'service_role_key';

    if v_project_url is null or v_service_key is null then
        raise warning 'notify_claimed_assignments: missing Vault secret project_url/service_role_key — skipping push';
        return new;
    end if;

    perform net.http_post(
        url := v_project_url || '/functions/v1/shift-notify',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || v_service_key
        ),
        body := jsonb_build_object(
            'type', 'assignment',
            'event_vendor_id', new.id,
            'event_id', new.event_id,
            'profile_id', new.profile_id,
            'block_title', coalesce(v_first_title, 'a block'),
            'block_count', v_count
        )
    );

    return new;
end;
$$;

comment on function public.notify_claimed_assignments()
    is 'AFTER UPDATE trigger fn on event_vendors: when an invite is claimed '
       '(profile_id null → set), POSTs one {type:assignment, block_count:N} '
       'summary to shift-notify so pre-claim block assignments are not lost.';

drop trigger if exists trg_notify_claimed_assignments on public.event_vendors;
create trigger trg_notify_claimed_assignments
    after update of profile_id on public.event_vendors
    for each row
    when (old.profile_id is null and new.profile_id is not null and new.deleted_at is null)
    execute function public.notify_claimed_assignments();
