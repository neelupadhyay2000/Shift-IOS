-- Marketplace Directory (vendor discovery) — Story 3b: vendor-portfolio policies
--
-- Path scheme: {profile_id}/{uuid}.jpg  (avatar: {profile_id}/avatar.jpg)
--
-- Access rules:
--   Read   → public (the bucket is public; directory imagery served via CDN)
--   Write  → folder owner only — insert/update/delete allowed only when the
--            first path segment equals the caller's uid.
--
-- The owner check uses storage.foldername(name)[1] = auth.uid()::text. A path
-- with no folder yields an empty array, so [1] is NULL and the predicate is
-- false — malformed paths are denied without a separate format guard.
-- ─────────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
-- SELECT: public read (bucket is public / CDN-served)
-- ─────────────────────────────────────────────────────────────────────────────
create policy "vendor_portfolio_public_read"
    on storage.objects for select
    to public
    using (bucket_id = 'vendor-portfolio');

-- ─────────────────────────────────────────────────────────────────────────────
-- INSERT: folder owner only — the {profile_id} folder must be the caller's uid
-- ─────────────────────────────────────────────────────────────────────────────
create policy "vendor_portfolio_owner_insert"
    on storage.objects for insert
    to authenticated
    with check (
        bucket_id = 'vendor-portfolio'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

-- ─────────────────────────────────────────────────────────────────────────────
-- UPDATE: folder owner only (re-upload / overwrite). USING gates the existing
-- object; WITH CHECK keeps the replacement inside the same owner's folder.
-- ─────────────────────────────────────────────────────────────────────────────
create policy "vendor_portfolio_owner_update"
    on storage.objects for update
    to authenticated
    using (
        bucket_id = 'vendor-portfolio'
        and (storage.foldername(name))[1] = auth.uid()::text
    )
    with check (
        bucket_id = 'vendor-portfolio'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

-- ─────────────────────────────────────────────────────────────────────────────
-- DELETE: folder owner only
-- ─────────────────────────────────────────────────────────────────────────────
create policy "vendor_portfolio_owner_delete"
    on storage.objects for delete
    to authenticated
    using (
        bucket_id = 'vendor-portfolio'
        and (storage.foldername(name))[1] = auth.uid()::text
    );
