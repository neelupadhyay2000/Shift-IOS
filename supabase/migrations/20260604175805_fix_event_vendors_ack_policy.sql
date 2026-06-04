-- Fix: event_vendors_vendor_update_ack infinite recursion
--
-- The original WITH CHECK subquery queried public.event_vendors to compare
-- old vs new values, which caused Postgres to re-evaluate the RLS policies
-- on that table — an infinite recursion.
--
-- Fix: extract the old-vs-new comparison into a SECURITY DEFINER function.
-- Security-definer functions bypass RLS, so the self-referential SELECT
-- inside it does not re-enter the policy evaluation loop.

create or replace function public.event_vendor_ack_only_changed(
    p_id  uuid,
    p_new public.event_vendors   -- the proposed new row (passed via WITH CHECK as event_vendors.*)
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_old public.event_vendors;
begin
    -- Reads the stored row bypassing RLS (security definer)
    select * into v_old from public.event_vendors where id = p_id;
    if not found then return false; end if;

    -- Every column except has_acknowledged_latest_shift (and updated_at, which
    -- the set_updated_at trigger bumps on every write) must be unchanged.
    return
        v_old.event_id                  = p_new.event_id
        and v_old.profile_id            is not distinct from p_new.profile_id
        and v_old.invited_phone         is not distinct from p_new.invited_phone
        and v_old.invited_email         is not distinct from p_new.invited_email
        and v_old.display_name          = p_new.display_name
        and v_old.role                  = p_new.role
        and v_old.notification_threshold = p_new.notification_threshold
        and v_old.pending_shift_delta   is not distinct from p_new.pending_shift_delta
        and v_old.invited_at            is not distinct from p_new.invited_at
        and v_old.accepted_at           is not distinct from p_new.accepted_at
        and v_old.created_at            = p_new.created_at
        and v_old.deleted_at            is not distinct from p_new.deleted_at;
end;
$$;

comment on function public.event_vendor_ack_only_changed(uuid, public.event_vendors)
    is 'Security-definer helper for the vendor ack UPDATE policy. '
       'Reads the stored row bypassing RLS and returns true only if every column '
       'except has_acknowledged_latest_shift (and updated_at) is unchanged.';

-- Replace the policy that caused infinite recursion
drop policy "event_vendors_vendor_update_ack" on public.event_vendors;

create policy "event_vendors_vendor_update_ack" on public.event_vendors
    for update
    to authenticated
    using (profile_id = auth.uid())
    with check (
        profile_id = auth.uid()
        and public.event_vendor_ack_only_changed(id, event_vendors.*)
    );
