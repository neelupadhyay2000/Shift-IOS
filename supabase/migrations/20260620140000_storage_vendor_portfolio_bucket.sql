-- Marketplace Directory (vendor discovery) — Story 3a: vendor-portfolio bucket
--
-- Public image bucket backing portfolio_items (kind='photo') and vendor avatars.
--
-- Path scheme: {profile_id}/{uuid}.jpg
--   e.g. 9f4e1a2b-…/3c7d8e0f-….jpg
-- Avatar:      {profile_id}/avatar.jpg
--   The avatar's resulting public URL is written to profiles.avatar_url (the
--   directory reads identity from profiles/public_profiles, not this bucket).
--
-- public = true: portfolio/avatar imagery is directory-facing and CDN-cacheable,
-- so objects are served straight from the public Storage URL (no signed URLs).
-- Writes are still gated — the folder-owner policies in the next migration
-- (20260620140100) restrict insert/update/delete to the {profile_id} owner.
--
-- Mirrors the voice-memos bucket migration (SHIFT-565), but public + image MIMEs.
-- ─────────────────────────────────────────────────────────────────────────────

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'vendor-portfolio',
    'vendor-portfolio',
    true,        -- public; directory imagery served via CDN
    10485760,    -- 10 MB per object
    array['image/jpeg', 'image/png', 'image/heic', 'image/webp']
);
