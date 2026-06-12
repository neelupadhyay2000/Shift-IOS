-- App-passcode sync: the access-layer passcode follows the ACCOUNT, so a
-- user who signs out and OTPs back in (same or new device) keeps their
-- existing passcode instead of re-creating one.
--
-- What is stored: an opaque client-derived record — 16-byte salt ‖ 32-byte
-- PBKDF2-HMAC-SHA256 digest (150k iterations), base64. Never the passcode.
-- Threat model: this is the privacy-shield PIN, not the account credential
-- (email OTP is); a leaked record costs an offline PBKDF2 brute-force of a
-- 6-digit space, and the record is useless without the device + session.
-- RLS is owner-only and the column appears in no view.
--
-- Restore flow (SupabaseAuthService.establishSession): remote record wins —
-- installing it locally after every sign-in also propagates passcode changes
-- made on another device. A local record uploads only when the server has
-- none (created offline; healed on next establishment).

create table public.app_passcodes (
    profile_id  uuid primary key references public.profiles(id) on delete cascade,
    record      text not null,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);

alter table public.app_passcodes enable row level security;

create policy "app_passcodes_self_all" on public.app_passcodes
    for all to authenticated
    using (profile_id = (select auth.uid()))
    with check (profile_id = (select auth.uid()));

create trigger trg_app_passcodes_updated_at
    before update on public.app_passcodes
    for each row
    execute function public.set_updated_at();

comment on table public.app_passcodes
    is 'Per-account app-lock passcode record (salted PBKDF2 digest, base64; '
       'never the passcode). Owner-only RLS; restored into the device Keychain '
       'after OTP sign-in so users keep their passcode across sign-outs/devices.';
