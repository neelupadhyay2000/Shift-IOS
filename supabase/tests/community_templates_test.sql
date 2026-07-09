-- Gate tests for the Community Templates RPCs (E23).
--
-- Self-contained: seeds fixtures, simulates auth via request.jwt.claims (what
-- auth.uid() reads), exercises the publish provenance gate / apply counter /
-- search read, and ROLLs BACK so it leaves no trace. Run against a local stack:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/community_templates_test.sql
-- RAISE EXCEPTIONs on the first failed assertion; a clean run ends with
-- "ALL COMMUNITY TEMPLATE TESTS PASSED".
--
-- Cases:
--   1. Publish without a source event → source_event_completed = false, author stamped.
--   2. Publish from a completed, caller-owned event → verified = true.
--   3. Publish from a non-completed (planning) event → verified = false.
--   4. Publish from another user's completed event → verified = false.
--   5. apply_community_template increments times_applied and returns the new total.
--   6. apply on an unpublished template returns NULL and does not increment.
--   7. search_community_templates returns only published rows, filters by category,
--      and resolves author_name.

begin;

set local client_min_messages = notice;

do $$
declare
    v_author   uuid := gen_random_uuid();
    v_other    uuid := gen_random_uuid();
    v_event    uuid := gen_random_uuid();   -- completed, owned by v_author
    v_planning uuid := gen_random_uuid();   -- planning, owned by v_author
    v_others   uuid := gen_random_uuid();   -- completed, owned by v_other
    v_blocks   jsonb := '[{"title":"Ceremony","relativeStartOffset":0,"duration":1800,"isPinned":true,"colorTag":"#FF9500","icon":"heart.fill"}]'::jsonb;
    v_tpl      public.community_templates;
    v_verified public.community_templates;
    v_id       uuid;
    v_count    int;
    v_applied  int;
begin
    -- ── Fixtures ──────────────────────────────────────────────────────────────
    insert into auth.users (id) values (v_author), (v_other);
    insert into public.profiles (id, display_name) values
        (v_author, 'Ava Author'),
        (v_other,  'Other Person');

    insert into public.events (id, owner_id, title, date, status) values
        (v_event,    v_author, 'Completed Event', now(), 'completed'),
        (v_planning, v_author, 'Planning Event',  now(), 'planning'),
        (v_others,   v_other,  'Other Completed', now(), 'completed');

    -- Act as the author for the RPC calls.
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_author::text)::text, true);

    -- ── Case 1: publish without a source event ───────────────────────────────
    select * into v_tpl from public.publish_community_template(
        'Unverified Wedding', 'no source', 'wedding', v_blocks, 1, null);
    if v_tpl.source_event_completed then
        raise exception 'CASE 1 FAILED: unverified publish was marked verified';
    end if;
    if v_tpl.author_id <> v_author then
        raise exception 'CASE 1 FAILED: author_id not stamped to caller';
    end if;
    raise notice 'case 1 ok: unverified, author stamped';

    -- ── Case 2: publish from a completed, owned event → verified ─────────────
    select * into v_verified from public.publish_community_template(
        'Verified Wedding', 'real run', 'wedding', v_blocks, 1, v_event);
    if not v_verified.source_event_completed then
        raise exception 'CASE 2 FAILED: completed owned event did not verify';
    end if;
    raise notice 'case 2 ok: verified from completed owned event';

    -- ── Case 3: publish from a non-completed event → not verified ────────────
    select * into v_tpl from public.publish_community_template(
        'From Planning', 'not done', 'social', v_blocks, 1, v_planning);
    if v_tpl.source_event_completed then
        raise exception 'CASE 3 FAILED: planning event should not verify';
    end if;
    raise notice 'case 3 ok: planning event not verified';

    -- ── Case 4: publish from another user's completed event → not verified ───
    select * into v_tpl from public.publish_community_template(
        'From Foreign Event', 'not mine', 'corporate', v_blocks, 1, v_others);
    if v_tpl.source_event_completed then
        raise exception 'CASE 4 FAILED: foreign event should not verify';
    end if;
    raise notice 'case 4 ok: foreign event not verified';

    -- ── Case 5: apply increments and returns the new total ───────────────────
    v_id := v_verified.id;
    v_applied := public.apply_community_template(v_id);
    if v_applied <> 1 then
        raise exception 'CASE 5 FAILED: expected times_applied 1, got %', coalesce(v_applied::text, 'null');
    end if;
    v_applied := public.apply_community_template(v_id);
    if v_applied <> 2 then
        raise exception 'CASE 5 FAILED: expected times_applied 2, got %', coalesce(v_applied::text, 'null');
    end if;
    raise notice 'case 5 ok: apply increments to %', v_applied;

    -- ── Case 6: apply on an unpublished template → NULL, no increment ────────
    update public.community_templates set is_published = false where id = v_id;
    v_applied := public.apply_community_template(v_id);
    if v_applied is not null then
        raise exception 'CASE 6 FAILED: apply on unpublished returned %', v_applied;
    end if;
    select times_applied into v_count from public.community_templates where id = v_id;
    if v_count <> 2 then
        raise exception 'CASE 6 FAILED: unpublished apply changed the counter to %', v_count;
    end if;
    -- Re-publish so it appears in the search assertions below.
    update public.community_templates set is_published = true where id = v_id;
    raise notice 'case 6 ok: unpublished apply is a no-op';

    -- ── Case 7: search filters by category + published, resolves author_name ─
    -- 'wedding' was used twice (cases 1 & 2); both published → expect 2.
    select count(*) into v_count
        from public.search_community_templates('wedding', '', 'popular', 30, 0);
    if v_count <> 2 then
        raise exception 'CASE 7 FAILED: expected 2 wedding templates, got %', v_count;
    end if;
    -- Author name resolves from profiles.display_name.
    if not exists (
        select 1 from public.search_community_templates('wedding', '', 'newest', 30, 0)
        where author_name = 'Ava Author'
    ) then
        raise exception 'CASE 7 FAILED: author_name not resolved';
    end if;
    -- Soft-delete one wedding template → search drops it.
    update public.community_templates set deleted_at = now()
        where category = 'wedding' and source_event_completed = false;
    select count(*) into v_count
        from public.search_community_templates('wedding', '', 'popular', 30, 0);
    if v_count <> 1 then
        raise exception 'CASE 7 FAILED: soft-deleted template still listed (got %)', v_count;
    end if;
    raise notice 'case 7 ok: search filters category/published/deleted + resolves author';

    raise notice 'ALL COMMUNITY TEMPLATE TESTS PASSED';
end;
$$;

rollback;
