-- SHIFT-555: block_vendors, block_dependencies, shift_records, device_tokens

-- ─────────────────────────────────────────────────────────────────────────────
-- block_vendors (M:N blocks ↔ event_vendors)
-- Composite PK; event_id denormalized for RLS and Realtime filtering.
-- ─────────────────────────────────────────────────────────────────────────────
create table public.block_vendors (
    block_id        uuid not null references public.blocks(id) on delete cascade,
    event_vendor_id uuid not null references public.event_vendors(id) on delete cascade,
    -- Denormalized: avoids a join in RLS policies and Realtime channel filters
    event_id        uuid not null references public.events(id) on delete cascade,
    created_at      timestamptz not null default now(),
    deleted_at      timestamptz,
    primary key (block_id, event_vendor_id)
);

alter table public.block_vendors enable row level security;

comment on table public.block_vendors
    is 'Which vendors are assigned to which blocks. '
       'event_id is denormalized for RLS/Realtime. '
       'RLS policies added in SHIFT-546.';

-- ─────────────────────────────────────────────────────────────────────────────
-- block_dependencies (self M:N blocks ↔ blocks)
-- Composite PK; event_id denormalized; self-reference guard prevents cycles.
-- ─────────────────────────────────────────────────────────────────────────────
create table public.block_dependencies (
    block_id            uuid not null references public.blocks(id) on delete cascade,
    depends_on_block_id uuid not null references public.blocks(id) on delete cascade,
    -- Denormalized: both blocks must belong to the same event
    event_id            uuid not null references public.events(id) on delete cascade,
    created_at          timestamptz not null default now(),
    deleted_at          timestamptz,
    primary key (block_id, depends_on_block_id),
    -- A block cannot depend on itself
    constraint block_dependencies_no_self_ref check (block_id != depends_on_block_id)
);

alter table public.block_dependencies enable row level security;

comment on table public.block_dependencies
    is 'Directed dependency edges between blocks (block_id depends on depends_on_block_id). '
       'event_id is denormalized for RLS/Realtime. '
       'RLS policies added in SHIFT-546.';

-- ─────────────────────────────────────────────────────────────────────────────
-- shift_records
-- Append-only audit log of every shift applied to an event timeline.
-- ─────────────────────────────────────────────────────────────────────────────
create table public.shift_records (
    id              uuid primary key default gen_random_uuid(),
    event_id        uuid not null references public.events(id) on delete cascade,
    -- Null when the shift was triggered globally rather than from a specific block
    source_block_id uuid references public.blocks(id) on delete set null,

    timestamp       timestamptz not null default now(),
    delta_minutes   integer not null,
    -- ShiftSource enum: manual | ripple | dependency | auto
    triggered_by    text not null default '',
    snapshot        jsonb,

    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now(),
    deleted_at      timestamptz
);

alter table public.shift_records enable row level security;

comment on table public.shift_records
    is 'Append-only audit log of shifts. source_block_id is null for global shifts. '
       'RLS policies added in SHIFT-546.';

-- ─────────────────────────────────────────────────────────────────────────────
-- device_tokens
-- APNs token registry per profile, for Edge Function push delivery (SHIFT-E15).
-- One row per device; a profile can have multiple devices (iPhone + iPad etc).
-- ─────────────────────────────────────────────────────────────────────────────
create table public.device_tokens (
    id          uuid primary key default gen_random_uuid(),
    profile_id  uuid not null references public.profiles(id) on delete cascade,
    apns_token  text not null,
    -- sandbox | prod — must match the app's aps-environment entitlement
    environment text not null default 'sandbox',
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now(),
    -- APNs tokens are globally unique per device
    unique (apns_token)
);

alter table public.device_tokens enable row level security;

comment on table public.device_tokens
    is 'APNs device token per profile. Used by Edge Functions in SHIFT-E15 to '
       'deliver shift push notifications when the vendor app is backgrounded. '
       'RLS policies added in SHIFT-546.';
