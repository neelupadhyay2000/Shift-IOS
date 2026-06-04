-- SHIFT-557: can_access_event() security-definer helper
--
-- Returns true when the calling user (auth.uid()) either:
--   a) owns the event (events.owner_id = auth.uid()), OR
--   b) is an accepted collaborator (event_vendors.profile_id = auth.uid())
--
-- Used as a shared predicate in every read-side RLS policy on child tables
-- (tracks, blocks, junctions, shift_records) so the membership logic is
-- defined once and updated in one place.
--
-- Security notes:
--   SECURITY DEFINER  — runs as the function owner (postgres), not the caller,
--                        so it can read events/event_vendors regardless of the
--                        caller's own row-level access.
--   search_path = ''  — prevents search_path hijacking; all references use
--                        explicit schema qualification (public.*).
--   STABLE            — no side-effects; same inputs → same result within a
--                        transaction. Allows the planner to cache the result.

create or replace function public.can_access_event(eid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select
        -- Caller owns the event
        exists (
            select 1
            from public.events e
            where e.id = eid
              and e.owner_id = auth.uid()
              and e.deleted_at is null
        )
        or
        -- Caller is an accepted vendor on the event
        exists (
            select 1
            from public.event_vendors v
            where v.event_id = eid
              and v.profile_id = auth.uid()
              and v.deleted_at is null
        )
$$;

comment on function public.can_access_event(uuid)
    is 'Returns true if auth.uid() owns the event or is an accepted vendor on it. '
       'Used as the shared read-access predicate in RLS policies for all child tables.';
