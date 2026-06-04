-- SHIFT-563: Indexes for hydration, delta-reconciliation, and Realtime queries.
--
-- Naming: idx_{table}_{columns}
--
-- Composite PKs on block_vendors(block_id, event_vendor_id) and
-- block_dependencies(block_id, depends_on_block_id) are already btree indexes
-- that cover block_id-prefix lookups; only the second FK column needs a
-- dedicated index for reverse lookups.
--
-- Tables with both event_id and updated_at get a compound (event_id, updated_at)
-- index rather than two separate ones: the compound covers the hydration query
-- (event_id = $1), the delta query (event_id = $1 AND updated_at > $2), and
-- the Realtime channel filter (event_id = eq.<id>) via the prefix.

-- ─────────────────────────────────────────────────────────────────────────────
-- events
-- Compound (owner_id, updated_at): owner hydration + per-owner delta fetch.
-- Standalone updated_at: global "what changed since last sync" across all
-- accessible events (includes collaborator events via RLS, not just owned ones).
-- ─────────────────────────────────────────────────────────────────────────────
create index idx_events_owner_id_updated_at
    on public.events(owner_id, updated_at);

create index idx_events_updated_at
    on public.events(updated_at);

-- ─────────────────────────────────────────────────────────────────────────────
-- tracks
-- ─────────────────────────────────────────────────────────────────────────────
create index idx_tracks_event_id_updated_at
    on public.tracks(event_id, updated_at);

-- ─────────────────────────────────────────────────────────────────────────────
-- blocks
-- track_id: FK reverse lookup (all blocks in a track); not covered by any PK.
-- ─────────────────────────────────────────────────────────────────────────────
create index idx_blocks_event_id_updated_at
    on public.blocks(event_id, updated_at);

create index idx_blocks_track_id
    on public.blocks(track_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- event_vendors
-- profile_id: claim-on-sign-in lookup + RLS predicate (v.profile_id = auth.uid()).
-- ─────────────────────────────────────────────────────────────────────────────
create index idx_event_vendors_event_id_updated_at
    on public.event_vendors(event_id, updated_at);

create index idx_event_vendors_profile_id
    on public.event_vendors(profile_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- block_vendors  (no updated_at column)
-- event_vendor_id: FK reverse — "all blocks assigned to this vendor".
-- ─────────────────────────────────────────────────────────────────────────────
create index idx_block_vendors_event_id
    on public.block_vendors(event_id);

create index idx_block_vendors_event_vendor_id
    on public.block_vendors(event_vendor_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- block_dependencies  (no updated_at column)
-- depends_on_block_id: FK reverse — "all blocks that depend on this block".
-- ─────────────────────────────────────────────────────────────────────────────
create index idx_block_dependencies_event_id
    on public.block_dependencies(event_id);

create index idx_block_dependencies_depends_on_block_id
    on public.block_dependencies(depends_on_block_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- shift_records
-- source_block_id: nullable FK; partial index excludes the common null case
-- (global shifts), keeping the index small and only covering block-specific ones.
-- ─────────────────────────────────────────────────────────────────────────────
create index idx_shift_records_event_id_updated_at
    on public.shift_records(event_id, updated_at);

create index idx_shift_records_source_block_id
    on public.shift_records(source_block_id)
    where source_block_id is not null;
