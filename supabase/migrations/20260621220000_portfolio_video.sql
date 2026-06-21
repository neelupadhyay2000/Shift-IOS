-- Portfolio video support (E23)
--
-- Allow 'video' portfolio items (stored in the vendor-portfolio bucket like
-- photos) and widen the bucket to accept video MIME types + larger objects.

-- kind: add 'video'.
alter table public.portfolio_items drop constraint portfolio_items_kind_check;
alter table public.portfolio_items
    add constraint portfolio_items_kind_check
    check (kind in ('photo', 'video', 'shift_event'));

-- payload coherence: a video, like a photo, needs a storage_path.
alter table public.portfolio_items drop constraint portfolio_items_kind_payload;
alter table public.portfolio_items
    add constraint portfolio_items_kind_payload
    check (
        (kind in ('photo', 'video') and storage_path is not null)
        or (kind = 'shift_event' and event_id is not null)
    );

-- Bucket: accept common video types and raise the size limit to 100 MB
-- (photos stay well under it). Storage owner-RLS policies are unchanged.
update storage.buckets
set allowed_mime_types = array[
        'image/jpeg', 'image/png', 'image/heic', 'image/webp',
        'video/mp4', 'video/quicktime'
    ],
    file_size_limit = 104857600
where id = 'vendor-portfolio';
