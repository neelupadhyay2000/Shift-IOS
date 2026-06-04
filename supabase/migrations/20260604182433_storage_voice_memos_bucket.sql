-- SHIFT-565: Create the voice-memos Storage bucket.
--
-- Path scheme: {event_id}/{block_id}.m4a
--   e.g. 9f4e1a2b-…/3c7d8e0f-….m4a
--
-- blocks.voice_memo_path stores the object key (not the full URL); the client
-- constructs the signed URL at download time so recordings are never exposed
-- via a guessable public URL.  Audio is lazily downloaded and cached on device.
--
-- Access policies are added in the next migration (SHIFT-566) and mirror event
-- access: the recording is only reachable if the caller can access the event
-- that owns the block.
--
-- MIME types accepted by iOS AVAudioRecorder when encoding M4A/AAC:
--   audio/mp4   — MPEG-4 container (the registered standard)
--   audio/x-m4a — Apple's file-extension-derived type (sent by some clients)
--   audio/aac   — raw AAC elementary stream (fallback)
-- ─────────────────────────────────────────────────────────────────────────────

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'voice-memos',
    'voice-memos',
    false,       -- private; signed URLs required (policies added in SHIFT-566)
    52428800,    -- 50 MB per object (~50 min of M4A at standard quality)
    array['audio/mp4', 'audio/x-m4a', 'audio/aac']
);
