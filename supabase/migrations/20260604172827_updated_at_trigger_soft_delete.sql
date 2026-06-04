-- SHIFT-556: updated_at bump trigger + soft-delete convention
--
-- updated_at drives delta reconciliation in E13 (fetch WHERE updated_at > lastPulledAt).
-- deleted_at is the tombstone for soft-deletes; offline devices use it to converge
-- on deletes they missed while disconnected.

-- ─────────────────────────────────────────────────────────────────────────────
-- Shared trigger function — one definition, applied to every table
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Attach trigger to every table that has an updated_at column
-- ─────────────────────────────────────────────────────────────────────────────
create trigger set_updated_at
    before update on public.profiles
    for each row execute function public.set_updated_at();

create trigger set_updated_at
    before update on public.events
    for each row execute function public.set_updated_at();

create trigger set_updated_at
    before update on public.tracks
    for each row execute function public.set_updated_at();

create trigger set_updated_at
    before update on public.blocks
    for each row execute function public.set_updated_at();

create trigger set_updated_at
    before update on public.event_vendors
    for each row execute function public.set_updated_at();

create trigger set_updated_at
    before update on public.shift_records
    for each row execute function public.set_updated_at();

create trigger set_updated_at
    before update on public.device_tokens
    for each row execute function public.set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- device_tokens was created without deleted_at — add it now for consistency
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.device_tokens
    add column deleted_at timestamptz;
