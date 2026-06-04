-- SHIFT-562: Add collaboration tables to the supabase_realtime publication.
--
-- Supabase creates the "supabase_realtime" publication automatically but with
-- no tables by default (publish_via_partition=false).  We add each table
-- individually so RLS is still respected: only rows the connected user can
-- SELECT are broadcast to their Realtime channel.
--
-- Tables added:
--   events, tracks, blocks          -- timeline core
--   event_vendors                   -- collaboration / invite state
--   block_vendors, block_dependencies -- junction tables
--   shift_records                   -- shift audit log
--
-- device_tokens is intentionally excluded: it carries APNs secrets and is
-- never needed by a Realtime subscriber on the client side.

alter publication supabase_realtime add table public.events;
alter publication supabase_realtime add table public.tracks;
alter publication supabase_realtime add table public.blocks;
alter publication supabase_realtime add table public.event_vendors;
alter publication supabase_realtime add table public.block_vendors;
alter publication supabase_realtime add table public.block_dependencies;
alter publication supabase_realtime add table public.shift_records;
