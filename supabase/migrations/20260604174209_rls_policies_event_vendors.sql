-- SHIFT-559: RLS policies — event_vendors
--
-- Three policies:
--   owner_all          → event owner has full CRUD
--   vendor_select      → vendor (profile_id = auth.uid()) reads its own row
--   vendor_update_ack  → vendor may update ONLY has_acknowledged_latest_shift
--
-- The ack-only restriction is enforced by comparing every other column in the
-- proposed new row against the stored row via a WITH CHECK subquery. If the
-- vendor tries to change any column except has_acknowledged_latest_shift the
-- subquery returns false and Postgres rejects the statement with a policy
-- violation error.
--
-- updated_at is intentionally excluded from the immutability check — the
-- set_updated_at trigger bumps it on every UPDATE and that is expected.

-- ─────────────────────────────────────────────────────────────────────────────
-- Owner: full CRUD
-- ─────────────────────────────────────────────────────────────────────────────
create policy "event_vendors_owner_all" on public.event_vendors
    for all
    to authenticated
    using (
        exists (
            select 1 from public.events e
            where e.id = event_vendors.event_id
              and e.owner_id = auth.uid()
        )
    )
    with check (
        exists (
            select 1 from public.events e
            where e.id = event_vendors.event_id
              and e.owner_id = auth.uid()
        )
    );

-- ─────────────────────────────────────────────────────────────────────────────
-- Vendor: read its own row
-- ─────────────────────────────────────────────────────────────────────────────
create policy "event_vendors_vendor_select" on public.event_vendors
    for select
    to authenticated
    using (profile_id = auth.uid());

-- ─────────────────────────────────────────────────────────────────────────────
-- Vendor: update ONLY has_acknowledged_latest_shift
--
-- USING   — row must belong to this vendor (profile_id = auth.uid())
-- WITH CHECK — every column except has_acknowledged_latest_shift must be
--              identical to the stored row; if the vendor sends a different
--              value for any other field the check fails.
-- ─────────────────────────────────────────────────────────────────────────────
create policy "event_vendors_vendor_update_ack" on public.event_vendors
    for update
    to authenticated
    using (profile_id = auth.uid())
    with check (
        profile_id = auth.uid()
        -- Compare proposed new values against the stored row.
        -- A mismatch on any of these columns means the vendor tried to
        -- change something they're not allowed to touch.
        and (
            select
                stored.event_id                  = event_vendors.event_id
                and stored.profile_id             is not distinct from event_vendors.profile_id
                and stored.invited_phone          is not distinct from event_vendors.invited_phone
                and stored.invited_email          is not distinct from event_vendors.invited_email
                and stored.display_name           = event_vendors.display_name
                and stored.role                   = event_vendors.role
                and stored.notification_threshold = event_vendors.notification_threshold
                and stored.pending_shift_delta    is not distinct from event_vendors.pending_shift_delta
                and stored.invited_at             is not distinct from event_vendors.invited_at
                and stored.accepted_at            is not distinct from event_vendors.accepted_at
                and stored.created_at             = event_vendors.created_at
                and stored.deleted_at             is not distinct from event_vendors.deleted_at
            from public.event_vendors stored
            where stored.id = event_vendors.id
        )
    );
