-- Marketplace Trust (E17) — Story 1: vendor_reviews + submit_vendor_review RPC
--
-- Reviews that cannot be faked. The table has NO direct INSERT policy at all — the
-- only write path is the SECURITY DEFINER RPC submit_vendor_review(), which verifies
-- that the caller owns the event, the event is completed, and the vendor actually
-- worked it (a claimed event_vendors row exists). Unique (event_id, vendor_profile_id)
-- enforces one review per worked event; a re-submit hits the constraint, while edits
-- go through the reviewer's own UPDATE policy.
--
-- Online-only by design (marketplace Services, same posture as vendor_profiles): not
-- part of the SwiftData/Outbox sync stack and not in the realtime publication.
--
-- RLS posture: public SELECT scoped to listed vendors (so reviews render on the
-- public profile), plus the reviewer's own SELECT/UPDATE (edit + soft-delete). No
-- INSERT policy — inserts only ever happen inside submit_vendor_review. anon revoked.

create table public.vendor_reviews (
    id                  uuid primary key default gen_random_uuid(),

    event_id            uuid not null references public.events(id) on delete cascade,
    vendor_profile_id   uuid not null references public.vendor_profiles(profile_id) on delete cascade,
    reviewer_id         uuid not null references public.profiles(id) on delete cascade,

    rating              smallint not null check (rating between 1 and 5),
    body                text not null default '' check (char_length(body) <= 2000),

    -- Sync metadata (repo convention; updated_at bumped by the trigger below).
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now(),
    deleted_at          timestamptz,

    -- One review per (event, vendor): a reviewer edits theirs, never stacks more.
    -- Spans soft-deleted rows on purpose — a deleted review still owns the slot.
    unique (event_id, vendor_profile_id)
);

comment on table public.vendor_reviews
    is 'Verified vendor reviews (E17). One per (event, vendor); written ONLY via the '
       'submit_vendor_review RPC (no direct INSERT policy) which gates on event '
       'ownership + completed status + a claimed event_vendors row. Online-only, not '
       'in the SwiftData sync stack or realtime publication. Reportable UGC '
       '(content_reports). RLS: public_select for listed vendors + reviewer self.';

-- ─────────────────────────────────────────────────────────────────────────────
-- Indexes
-- ─────────────────────────────────────────────────────────────────────────────
-- Profile detail: list a vendor's reviews newest-first.
create index vendor_reviews_vendor_idx
    on public.vendor_reviews (vendor_profile_id, created_at desc);

-- Reviewer's own reviews (composer "did I already review this?" + edit path).
create index vendor_reviews_reviewer_idx
    on public.vendor_reviews (reviewer_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- updated_at bump — shared trigger function from SHIFT-556
-- ─────────────────────────────────────────────────────────────────────────────
create trigger set_updated_at
    before update on public.vendor_reviews
    for each row execute function public.set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- RLS — note: deliberately NO insert policy (see submit_vendor_review below).
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.vendor_reviews enable row level security;

-- Directory: any authenticated user may read reviews of a listed, non-deleted
-- vendor (the reviews section on the public profile). Soft-deleted reviews are
-- filtered by the app layer, matching the rest of the marketplace.
create policy "vendor_reviews_public_select" on public.vendor_reviews
    for select
    to authenticated
    using (
        exists (
            select 1
            from public.vendor_profiles vp
            where vp.profile_id = vendor_reviews.vendor_profile_id
              and vp.is_listed
              and vp.deleted_at is null
        )
    );

-- Reviewer: read own review even when the vendor is unlisted (so the composer can
-- detect/load it for editing).
create policy "vendor_reviews_reviewer_select" on public.vendor_reviews
    for select
    to authenticated
    using (reviewer_id = auth.uid());

-- Reviewer: edit / soft-delete own review. The immutability guard keeps the
-- gated keys (event, vendor, reviewer) frozen — only rating/body/deleted_at move.
create policy "vendor_reviews_reviewer_update" on public.vendor_reviews
    for update
    to authenticated
    using (reviewer_id = auth.uid())
    with check (
        reviewer_id = auth.uid()
        and (
            select
                stored.event_id          = vendor_reviews.event_id
                and stored.vendor_profile_id = vendor_reviews.vendor_profile_id
                and stored.reviewer_id       = vendor_reviews.reviewer_id
                and stored.created_at        = vendor_reviews.created_at
            from public.vendor_reviews stored
            where stored.id = vendor_reviews.id
        )
    );

-- Authenticated-only marketplace: revoke the Data API's auto-grants to anon.
revoke all on public.vendor_reviews from anon;

-- ─────────────────────────────────────────────────────────────────────────────
-- submit_vendor_review() — the ONLY write path into vendor_reviews.
--
-- SECURITY DEFINER so it can INSERT past the (intentionally absent) insert policy,
-- but it re-checks every trust condition itself before writing:
--   1. caller is authenticated;
--   2. the event exists, is owned by the caller, and is status = 'completed';
--   3. a claimed event_vendors row links that vendor to that event
--      (profile_id = vendor, accepted_at not null, not soft-deleted).
-- The unique (event_id, vendor_profile_id) constraint blocks a second review;
-- callers should route a re-review through the reviewer UPDATE policy instead.
-- search_path = '' with fully-qualified names per repo convention.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.submit_vendor_review(
    p_event_id          uuid,
    p_vendor_profile_id uuid,
    p_rating            smallint,
    p_body              text default ''
)
returns setof public.vendor_reviews
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_uid uuid := auth.uid();
begin
    if v_uid is null then
        raise exception 'submit_vendor_review: not authenticated'
            using errcode = '28000';
    end if;

    -- Gate 1+2: caller owns the event and it is completed.
    if not exists (
        select 1
        from public.events e
        where e.id = p_event_id
          and e.owner_id = v_uid
          and e.status = 'completed'
          and e.deleted_at is null
    ) then
        raise exception
            'submit_vendor_review: event % is not a completed event owned by the caller', p_event_id
            using errcode = '42501';
    end if;

    -- Gate 3: the vendor actually worked this event (claimed event_vendors row).
    if not exists (
        select 1
        from public.event_vendors ev
        where ev.event_id = p_event_id
          and ev.profile_id = p_vendor_profile_id
          and ev.accepted_at is not null
          and ev.deleted_at is null
    ) then
        raise exception
            'submit_vendor_review: vendor % did not work event %', p_vendor_profile_id, p_event_id
            using errcode = 'P0001';
    end if;

    -- All gates passed. The unique constraint enforces one-per-worked-event; a
    -- duplicate surfaces as a unique_violation (errcode 23505) to the caller.
    return query
    insert into public.vendor_reviews
        (event_id, vendor_profile_id, reviewer_id, rating, body)
    values
        (p_event_id, p_vendor_profile_id, v_uid, p_rating, coalesce(p_body, ''))
    returning *;
end;
$$;

comment on function public.submit_vendor_review(uuid, uuid, smallint, text)
    is 'The only write path into vendor_reviews. Verifies the caller owns the '
       'event, the event is completed, and a claimed event_vendors row links the '
       'vendor to the event, then inserts the review. Unique (event_id, '
       'vendor_profile_id) blocks duplicates; edits go through the reviewer UPDATE '
       'policy. SECURITY DEFINER, authenticated-only.';

-- Lock the RPC down to authenticated callers.
revoke all on function public.submit_vendor_review(uuid, uuid, smallint, text) from public, anon;
grant execute on function public.submit_vendor_review(uuid, uuid, smallint, text) to authenticated;
