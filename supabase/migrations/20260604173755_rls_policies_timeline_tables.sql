-- SHIFT-558: RLS policies — events / tracks / blocks / junctions / shift_records
--
-- Pattern for every table:
--   owner_all       → event owner has INSERT + UPDATE + DELETE + SELECT
--   collaborator_select → can_access_event() grants SELECT (covers owner + vendors)
--
-- Multiple policies use OR semantics in Postgres — a row is accessible if it
-- matches ANY policy. The collaborator_select policy therefore also covers the
-- owner's SELECTs, while owner_all is the sole gate for writes.
--
-- deleted_at is intentionally not filtered in RLS: the owner needs to be able
-- to write the deleted_at tombstone, and the app layer handles "show only
-- non-deleted rows" in its queries. Tombstone rows must propagate to offline
-- clients so they converge on deletes (SHIFT-E13).

-- ─────────────────────────────────────────────────────────────────────────────
-- events
-- Owner check is direct (events.owner_id); no join needed.
-- ─────────────────────────────────────────────────────────────────────────────
create policy "events_owner_all" on public.events
    for all
    to authenticated
    using (owner_id = auth.uid())
    with check (owner_id = auth.uid());

create policy "events_collaborator_select" on public.events
    for select
    to authenticated
    using (public.can_access_event(id));

-- ─────────────────────────────────────────────────────────────────────────────
-- tracks
-- ─────────────────────────────────────────────────────────────────────────────
create policy "tracks_owner_all" on public.tracks
    for all
    to authenticated
    using (
        exists (
            select 1 from public.events e
            where e.id = tracks.event_id
              and e.owner_id = auth.uid()
        )
    )
    with check (
        exists (
            select 1 from public.events e
            where e.id = tracks.event_id
              and e.owner_id = auth.uid()
        )
    );

create policy "tracks_collaborator_select" on public.tracks
    for select
    to authenticated
    using (public.can_access_event(event_id));

-- ─────────────────────────────────────────────────────────────────────────────
-- blocks
-- ─────────────────────────────────────────────────────────────────────────────
create policy "blocks_owner_all" on public.blocks
    for all
    to authenticated
    using (
        exists (
            select 1 from public.events e
            where e.id = blocks.event_id
              and e.owner_id = auth.uid()
        )
    )
    with check (
        exists (
            select 1 from public.events e
            where e.id = blocks.event_id
              and e.owner_id = auth.uid()
        )
    );

create policy "blocks_collaborator_select" on public.blocks
    for select
    to authenticated
    using (public.can_access_event(event_id));

-- ─────────────────────────────────────────────────────────────────────────────
-- block_vendors
-- ─────────────────────────────────────────────────────────────────────────────
create policy "block_vendors_owner_all" on public.block_vendors
    for all
    to authenticated
    using (
        exists (
            select 1 from public.events e
            where e.id = block_vendors.event_id
              and e.owner_id = auth.uid()
        )
    )
    with check (
        exists (
            select 1 from public.events e
            where e.id = block_vendors.event_id
              and e.owner_id = auth.uid()
        )
    );

create policy "block_vendors_collaborator_select" on public.block_vendors
    for select
    to authenticated
    using (public.can_access_event(event_id));

-- ─────────────────────────────────────────────────────────────────────────────
-- block_dependencies
-- ─────────────────────────────────────────────────────────────────────────────
create policy "block_dependencies_owner_all" on public.block_dependencies
    for all
    to authenticated
    using (
        exists (
            select 1 from public.events e
            where e.id = block_dependencies.event_id
              and e.owner_id = auth.uid()
        )
    )
    with check (
        exists (
            select 1 from public.events e
            where e.id = block_dependencies.event_id
              and e.owner_id = auth.uid()
        )
    );

create policy "block_dependencies_collaborator_select" on public.block_dependencies
    for select
    to authenticated
    using (public.can_access_event(event_id));

-- ─────────────────────────────────────────────────────────────────────────────
-- shift_records
-- ─────────────────────────────────────────────────────────────────────────────
create policy "shift_records_owner_all" on public.shift_records
    for all
    to authenticated
    using (
        exists (
            select 1 from public.events e
            where e.id = shift_records.event_id
              and e.owner_id = auth.uid()
        )
    )
    with check (
        exists (
            select 1 from public.events e
            where e.id = shift_records.event_id
              and e.owner_id = auth.uid()
        )
    );

create policy "shift_records_collaborator_select" on public.shift_records
    for select
    to authenticated
    using (public.can_access_event(event_id));
