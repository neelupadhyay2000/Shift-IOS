-- SHIFT-553: events, tracks, blocks
-- events   → owned by a profile (owner_id replaces CloudKit ownerRecordName)
-- tracks   → child of events, cascade-deleted
-- blocks   → child of tracks, cascade-deleted; carries denormalized event_id
--            for RLS and Realtime channel filtering without a join

-- ─────────────────────────────────────────────────────────────────────────────
-- events
-- ─────────────────────────────────────────────────────────────────────────────
create table public.events (
    id                  uuid primary key default gen_random_uuid(),
    owner_id            uuid not null references public.profiles(id) on delete cascade,

    title               text not null default '',
    date                timestamptz not null,
    latitude            double precision,
    longitude           double precision,
    venue_names         text[] not null default '{}',

    sunset_time         timestamptz,
    golden_hour_start   timestamptz,
    weather_snapshot    jsonb,

    -- EventStatus: planning | live | completed
    status              text not null default 'planning',
    went_live_at        timestamptz,
    completed_at        timestamptz,
    last_shifted_at     timestamptz,

    post_event_report   jsonb,

    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now(),
    deleted_at          timestamptz
);

alter table public.events enable row level security;

comment on table public.events
    is 'Top-level event owned by a planner profile. '
       'owner_id replaces CloudKit ownerRecordName. '
       'RLS policies added in SHIFT-546.';

-- ─────────────────────────────────────────────────────────────────────────────
-- tracks
-- ─────────────────────────────────────────────────────────────────────────────
create table public.tracks (
    id          uuid primary key default gen_random_uuid(),
    event_id    uuid not null references public.events(id) on delete cascade,

    name        text not null default '',
    sort_order  integer not null default 0,
    is_default  boolean not null default false,

    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now(),
    deleted_at  timestamptz
);

alter table public.tracks enable row level security;

comment on table public.tracks
    is 'Timeline tracks belonging to an event. '
       'RLS policies added in SHIFT-546.';

-- ─────────────────────────────────────────────────────────────────────────────
-- blocks
-- ─────────────────────────────────────────────────────────────────────────────
create table public.blocks (
    id                      uuid primary key default gen_random_uuid(),
    track_id                uuid not null references public.tracks(id) on delete cascade,
    -- Denormalized: lets RLS and Realtime filter by event_id without a join
    event_id                uuid not null references public.events(id) on delete cascade,

    title                   text not null default '',
    scheduled_start         timestamptz not null,
    original_start          timestamptz not null,
    duration                double precision not null default 0,
    minimum_duration        double precision not null default 0,
    is_pinned               boolean not null default false,

    notes                   text not null default '',
    -- voice_memo_path is a Supabase Storage key, e.g. {event_id}/{block_id}.m4a
    voice_memo_path         text,
    voice_memo_duration     double precision,
    voice_memo_created_at   timestamptz,

    color_tag               text not null default '',
    icon                    text not null default '',
    -- BlockStatus: upcoming | inProgress | completed | skipped
    status                  text not null default 'upcoming',

    requires_review         boolean not null default false,
    is_outdoor              boolean not null default false,
    venue_address           text not null default '',
    venue_name              text not null default '',
    block_latitude          double precision,
    block_longitude         double precision,
    is_transit_block        boolean not null default false,

    completed_time          timestamptz,

    created_at              timestamptz not null default now(),
    updated_at              timestamptz not null default now(),
    deleted_at              timestamptz
);

alter table public.blocks enable row level security;

comment on table public.blocks
    is 'Timeline blocks belonging to a track. '
       'event_id is denormalized for RLS and Realtime filtering. '
       'RLS policies added in SHIFT-546.';
