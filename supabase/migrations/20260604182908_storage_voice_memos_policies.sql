-- SHIFT-566: Storage access policies for the voice-memos bucket.
--
-- Path scheme: {event_id}/{block_id}.m4a
--
-- Access rules (mirror event access — same model as timeline RLS):
--   Owner     → SELECT + INSERT + UPDATE + DELETE
--   Vendor    → SELECT only (read the block's memo; cannot record)
--   Stranger  → nothing
--
-- Two helper functions extract the UUID segments from the object name and
-- return NULL for any path that doesn't match the expected scheme.  All four
-- policies rely on null-safe predicates, so a malformed path is automatically
-- denied without a separate format guard:
--   can_access_event(null)          → false  (EXISTS … WHERE id = null)
--   EXISTS … WHERE id = null        → false  (null = null is never true)
-- ─────────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
-- Path-parsing helpers
-- security definer so they can query public.events/blocks without the caller
-- needing direct table access; search_path pinned to prevent search-path injection.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.storage_voice_memo_event_id(object_name text)
returns uuid
language sql stable security definer
set search_path = public
as $$
    select case
        when object_name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.m4a$'
        then split_part(object_name, '/', 1)::uuid
        else null
    end;
$$;

create or replace function public.storage_voice_memo_block_id(object_name text)
returns uuid
language sql stable security definer
set search_path = public
as $$
    select case
        when object_name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.m4a$'
        then split_part(split_part(object_name, '/', 2), '.', 1)::uuid
        else null
    end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- SELECT: owner and accepted vendors can download
-- ─────────────────────────────────────────────────────────────────────────────
create policy "voice_memos_read"
    on storage.objects for select
    to authenticated
    using (
        bucket_id = 'voice-memos'
        and public.can_access_event(public.storage_voice_memo_event_id(name))
    );

-- ─────────────────────────────────────────────────────────────────────────────
-- INSERT: owner only; the target block must exist inside the event.
-- Validates referential integrity at upload time so orphaned audio objects
-- cannot accumulate (the block row must already be in the DB when recording).
-- ─────────────────────────────────────────────────────────────────────────────
create policy "voice_memos_owner_upload"
    on storage.objects for insert
    to authenticated
    with check (
        bucket_id = 'voice-memos'
        and exists (
            select 1 from public.events
            where id        = public.storage_voice_memo_event_id(name)
              and owner_id  = auth.uid()
        )
        and exists (
            select 1 from public.blocks
            where id        = public.storage_voice_memo_block_id(name)
              and event_id  = public.storage_voice_memo_event_id(name)
        )
    );

-- ─────────────────────────────────────────────────────────────────────────────
-- UPDATE: owner only (re-record / overwrite)
-- USING targets the existing object; WITH CHECK validates the replacement path.
-- Path must still belong to the same owner's event after the update.
-- ─────────────────────────────────────────────────────────────────────────────
create policy "voice_memos_owner_update"
    on storage.objects for update
    to authenticated
    using (
        bucket_id = 'voice-memos'
        and exists (
            select 1 from public.events
            where id        = public.storage_voice_memo_event_id(name)
              and owner_id  = auth.uid()
        )
    )
    with check (
        bucket_id = 'voice-memos'
        and exists (
            select 1 from public.events
            where id        = public.storage_voice_memo_event_id(name)
              and owner_id  = auth.uid()
        )
    );

-- ─────────────────────────────────────────────────────────────────────────────
-- DELETE: owner only
-- ─────────────────────────────────────────────────────────────────────────────
create policy "voice_memos_owner_delete"
    on storage.objects for delete
    to authenticated
    using (
        bucket_id = 'voice-memos'
        and exists (
            select 1 from public.events
            where id        = public.storage_voice_memo_event_id(name)
              and owner_id  = auth.uid()
        )
    );
