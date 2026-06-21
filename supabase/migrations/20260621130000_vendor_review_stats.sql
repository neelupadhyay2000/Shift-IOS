-- Marketplace Trust (E17) — Story 2: hot-path stat counters + profile-detail view
--
-- Two tiers of "Verified by Shift" stats:
--   1. Hot path (search/directory cards): trigger-maintained counters on
--      vendor_profiles so a card render is a single-row read, never an aggregate.
--        - recompute_vendor_rating(): on any vendor_reviews change, recompute
--          rating_avg / rating_count for the affected vendor.
--        - bump_events_completed_count(): when an event transitions INTO
--          'completed', +1 events_completed_count for every claimed vendor.
--      Plus a one-time backfill for events already completed before this trigger.
--   2. Profile detail: the vendor_public_stats view (SECURITY DEFINER semantics)
--      computes the richer, less-frequently-read metrics on demand.

-- ─────────────────────────────────────────────────────────────────────────────
-- Tier 1a: ratings — recompute on every vendor_reviews change
-- ─────────────────────────────────────────────────────────────────────────────
-- Authoritative recompute (not incremental): cheap (one vendor's reviews) and
-- immune to drift from edits / soft-deletes / hard-deletes. Counts only live
-- (deleted_at is null) reviews; rating_avg stays null when none remain.
create or replace function public.recompute_vendor_rating()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_vendor uuid := coalesce(new.vendor_profile_id, old.vendor_profile_id);
begin
    update public.vendor_profiles vp
       set rating_count = stats.cnt,
           rating_avg   = stats.avg
      from (
          select count(*)::int            as cnt,
                 avg(rating)::numeric(3,2) as avg
            from public.vendor_reviews
           where vendor_profile_id = v_vendor
             and deleted_at is null
      ) stats
     where vp.profile_id = v_vendor;
    return null;   -- AFTER trigger; return value ignored
end;
$$;

comment on function public.recompute_vendor_rating()
    is 'AFTER trigger fn (E17): recomputes vendor_profiles.rating_avg/rating_count '
       'for the affected vendor from live (non-deleted) vendor_reviews.';

drop trigger if exists trg_recompute_vendor_rating on public.vendor_reviews;
create trigger trg_recompute_vendor_rating
    after insert or delete or update of rating, deleted_at on public.vendor_reviews
    for each row execute function public.recompute_vendor_rating();

-- ─────────────────────────────────────────────────────────────────────────────
-- Tier 1b: events completed — bump on the transition INTO 'completed'
-- ─────────────────────────────────────────────────────────────────────────────
-- Increment events_completed_count for every CLAIMED vendor on the event
-- (profile_id set, accepted_at set, not soft-deleted). The WHEN guard
-- (old.status <> 'completed') prevents double-counting on a completed→live→
-- completed flip. Minor drift from edge cases is acceptable for v1; a nightly
-- recount RPC is noted future work. Vendors without a vendor_profiles row
-- (collaborators who aren't marketplace vendors) are simply not counted.
create or replace function public.bump_events_completed_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    update public.vendor_profiles vp
       set events_completed_count = vp.events_completed_count + 1
     where vp.profile_id in (
         select ev.profile_id
           from public.event_vendors ev
          where ev.event_id = new.id
            and ev.profile_id is not null
            and ev.accepted_at is not null
            and ev.deleted_at is null
     );
    return null;
end;
$$;

comment on function public.bump_events_completed_count()
    is 'AFTER UPDATE OF status trigger fn (E17): on the transition into '
       'completed, +1 events_completed_count for each claimed vendor. Guarded '
       'against double-count by the trigger WHEN clause. Drift is recounted by a '
       'future nightly RPC.';

drop trigger if exists trg_bump_events_completed_count on public.events;
create trigger trg_bump_events_completed_count
    after update of status on public.events
    for each row
    when (new.status = 'completed' and old.status <> 'completed')
    execute function public.bump_events_completed_count();

-- ─────────────────────────────────────────────────────────────────────────────
-- One-time backfill: events already completed before the trigger existed.
-- SET (authoritative) rather than increment — the column is at its default 0 for
-- everyone, and these events will never transition again, so there's nothing for
-- the trigger to double-count.
-- ─────────────────────────────────────────────────────────────────────────────
update public.vendor_profiles vp
   set events_completed_count = sub.cnt
  from (
      select ev.profile_id,
             count(distinct ev.event_id) as cnt
        from public.event_vendors ev
        join public.events e on e.id = ev.event_id
       where e.status = 'completed'
         and e.deleted_at is null
         and ev.profile_id is not null
         and ev.accepted_at is not null
         and ev.deleted_at is null
       group by ev.profile_id
  ) sub
 where vp.profile_id = sub.profile_id;

-- ─────────────────────────────────────────────────────────────────────────────
-- Tier 2: vendor_public_stats — profile-detail metrics, computed on demand.
--
-- SECURITY DEFINER semantics: a plain (non-security_invoker) view runs with the
-- owner's rights, so it reads events / event_vendors past the caller's RLS to
-- compute cross-event reliability. Exposure is bounded to LISTED, non-deleted
-- vendors (opted into the public directory) — the same surface as the public
-- profile that renders these numbers. Intended to be queried filtered to one
-- profile_id (the profile detail screen): `... where profile_id = $1`.
--
-- Metrics:
--   events_completed     — distinct completed events the vendor worked (claimed)
--   repeat_planner_count — planners who hired this vendor for 2+ completed events
--   reliability_pct      — % of completed events whose event_vendors row ended
--                          acknowledged OR with no pending shift delta
--
-- FUTURE WORK (NOT built now): a true ack-latency metric (how fast a vendor
-- acknowledges each shift) needs a shift_acks audit table recording every ack
-- with its server timestamp. v1's reliability is the coarse end-state proxy
-- above; the audit table + latency percentiles are deferred.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace view public.vendor_public_stats as
with worked as (
    select ev.profile_id,
           e.id       as event_id,
           e.owner_id,
           (ev.has_acknowledged_latest_shift
              or coalesce(ev.pending_shift_delta, 0) = 0) as clean
      from public.event_vendors ev
      join public.events e on e.id = ev.event_id
     where e.status = 'completed'
       and e.deleted_at is null
       and ev.profile_id is not null
       and ev.accepted_at is not null
       and ev.deleted_at is null
),
planner_counts as (
    select profile_id, owner_id, count(distinct event_id) as n
      from worked
     group by profile_id, owner_id
),
repeat_planners as (
    select profile_id, count(*)::int as repeat_planner_count
      from planner_counts
     where n >= 2
     group by profile_id
)
select
    vp.profile_id,
    count(distinct w.event_id)::int           as events_completed,
    coalesce(rp.repeat_planner_count, 0)      as repeat_planner_count,
    case
        when count(w.event_id) > 0
        then round(100.0 * count(*) filter (where w.clean) / count(w.event_id))::int
    end                                       as reliability_pct
  from public.vendor_profiles vp
  left join worked w           on w.profile_id = vp.profile_id
  left join repeat_planners rp on rp.profile_id = vp.profile_id
 where vp.is_listed
   and vp.deleted_at is null
 group by vp.profile_id, rp.repeat_planner_count;

comment on view public.vendor_public_stats
    is 'Profile-detail "Verified by Shift" stats for LISTED vendors (E17). '
       'Definer-semantics view: reads events/event_vendors past caller RLS to '
       'compute reliability. Query filtered to one profile_id. reliability_pct is '
       'a v1 end-state proxy; true ack-latency needs a future shift_acks table.';

-- Authenticated-only (matches the rest of the marketplace); never anon.
revoke all on public.vendor_public_stats from anon;
grant select on public.vendor_public_stats to authenticated;
