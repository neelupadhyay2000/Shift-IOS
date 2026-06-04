-- SHIFT-552: profiles
-- One row per authenticated user, keyed to auth.users.
-- Marketplace columns (avatar_url, business_name, bio, portfolio_url) are reserved
-- now so the future marketplace feature needs no disruptive migration.

create table public.profiles (
    id              uuid primary key references auth.users(id) on delete cascade,
    display_name    text not null default '',
    phone           text,
    email           text,
    default_role    text,

    -- Marketplace: reserved, nullable, unused at launch
    avatar_url      text,
    business_name   text,
    bio             text,
    portfolio_url   text,

    -- Sync metadata (updated_at trigger added in SHIFT-556)
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now(),
    deleted_at      timestamptz
);

alter table public.profiles enable row level security;

comment on table public.profiles
    is 'One row per authenticated user mirroring auth.users. '
       'Marketplace columns reserved for future vendor discovery; '
       'RLS policies added in SHIFT-546.';
