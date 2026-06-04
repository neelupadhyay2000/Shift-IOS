-- SHIFT-554: event_vendors
-- Represents a vendor's relationship to an event.
--
-- Three states:
--   contact-only  → profile_id null, invited_at null  (call-list / PDF only)
--   invited       → profile_id null, invited_at set   (invite sent, not yet claimed)
--   collaborator  → profile_id set,  accepted_at set  (claimed on sign-in)
--
-- profile_id is nullable by design: it stays null until the invited person signs
-- in and the claim-on-sign-in flow matches invited_phone / invited_email → sets
-- profile_id and accepted_at. RLS uses this distinction to gate vendor access.

create table public.event_vendors (
    id                              uuid primary key default gen_random_uuid(),
    event_id                        uuid not null references public.events(id) on delete cascade,
    -- Null until the invitee signs in and claims the invite
    profile_id                      uuid references public.profiles(id) on delete set null,

    -- What the invite was sent to; used for claim matching on sign-in
    invited_phone                   text,
    invited_email                   text,

    -- Display name shown even for contact-only vendors (no profile)
    display_name                    text not null default '',

    -- VendorRole enum stored as text
    role                            text not null default '',

    -- Shift notification threshold in seconds
    notification_threshold          integer not null default 0,

    -- Acknowledgement state (vendor-writable; planner reads via Realtime)
    has_acknowledged_latest_shift   boolean not null default false,
    pending_shift_delta             double precision,

    -- Invite lifecycle timestamps
    invited_at                      timestamptz,
    accepted_at                     timestamptz,

    created_at                      timestamptz not null default now(),
    updated_at                      timestamptz not null default now(),
    deleted_at                      timestamptz
);

alter table public.event_vendors enable row level security;

comment on table public.event_vendors
    is 'Per-event vendor relationship. profile_id is null for contact-only vendors '
       'and for invited vendors who have not yet claimed. '
       'Claim-on-sign-in sets profile_id + accepted_at. '
       'RLS policies added in SHIFT-546.';

comment on column public.event_vendors.profile_id
    is 'Null until the invited person signs in and the invite is claimed by matching '
       'invited_phone or invited_email to their auth profile.';
