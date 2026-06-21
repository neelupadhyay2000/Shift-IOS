-- Marketplace Directory (vendor discovery) — Story 8: claimable portfolio events
--
-- Backs the portfolio editor's "Add a Shift event" picker: the completed events
-- where the caller was an accepted vendor and which they haven't already added as
-- a (non-deleted) shift_event portfolio item. Same gate the portfolio_items_verify
-- trigger enforces on insert — this just lists the eligible candidates.
--
-- SECURITY DEFINER so it can read events/event_vendors without widening their RLS
-- (mirrors get_portfolio_event_summaries). Returns the same shape so the client
-- reuses PortfolioEventSummaryDTO.

create or replace function public.get_claimable_portfolio_events()
returns table (event_id uuid, title text, event_date timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
    select e.id, e.title, e.date
    from public.event_vendors v
    join public.events e on e.id = v.event_id
    where v.profile_id = auth.uid()
      and v.accepted_at is not null
      and v.deleted_at is null
      and e.status = 'completed'
      and e.deleted_at is null
      and not exists (
          select 1
          from public.portfolio_items pi
          where pi.profile_id = auth.uid()
            and pi.kind = 'shift_event'
            and pi.event_id = e.id
            and pi.deleted_at is null
      )
    order by e.date desc;
$$;

comment on function public.get_claimable_portfolio_events()
    is 'Completed events where auth.uid() was an accepted vendor and which are not '
       'already in their portfolio — candidates for the "Add a Shift event" '
       'picker. SECURITY DEFINER; events RLS unwidened.';

revoke all on function public.get_claimable_portfolio_events() from public;
revoke all on function public.get_claimable_portfolio_events() from anon;
grant execute on function public.get_claimable_portfolio_events() to authenticated;
