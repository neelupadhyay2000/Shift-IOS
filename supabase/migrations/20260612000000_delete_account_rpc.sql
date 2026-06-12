-- delete_account() — in-app account deletion (App Store Guideline 5.1.1(v))
--
-- A client cannot delete its own auth.users row: that table is owned by the
-- auth schema and admin deletion requires the service-role key, which never
-- ships in the app. We therefore expose a SECURITY DEFINER function scoped to
-- the caller's own verified identity (auth.uid()) — a user can delete exactly
-- one account: their own.
--
-- Deletion order matters:
--   1. Voice-memo storage objects are removed first. They are keyed
--      "{event_id}/{block_id}.m4a" but storage.objects has no FK to events,
--      so the cascade in step 2 would orphan them.
--   2. Deleting the auth.users row cascades through the relational graph:
--      profiles → events (owner_id) → tracks / blocks / event_vendors /
--      block_assignments / block_dependencies / shift_records, and
--      device_tokens via profiles.
--
-- What deliberately survives: event_vendors.profile_id on OTHER planners'
-- events is ON DELETE SET NULL — a vendor deleting their account unlinks
-- from events they were invited to, but never destroys someone else's data.

create or replace function public.delete_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    caller uuid := auth.uid();
begin
    if caller is null then
        raise exception 'delete_account() requires an authenticated caller';
    end if;

    delete from storage.objects
    where bucket_id = 'voice-memos'
      and public.storage_voice_memo_event_id(name) in (
          select e.id from public.events e where e.owner_id = caller
      );

    delete from auth.users where id = caller;
end;
$$;

revoke all on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;
