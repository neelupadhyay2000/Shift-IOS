-- Marketplace Trust (E17) — Story 2: review_received push trigger
--
-- AFTER INSERT on vendor_reviews → POST {type:'review_received'} to the
-- shift-notify Edge Function so the reviewed vendor gets an alert push
-- ("You received a {rating}-star review"). The edge fn resolves the vendor's
-- device tokens (service role) and builds the body from the rating. Same Vault
-- pattern + graceful degrade as the other notify triggers.

create extension if not exists pg_net;

create or replace function public.notify_vendor_review()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_project_url text;
    v_service_key text;
begin
    select decrypted_secret into v_project_url
        from vault.decrypted_secrets where name = 'project_url';
    select decrypted_secret into v_service_key
        from vault.decrypted_secrets where name = 'service_role_key';

    if v_project_url is null or v_service_key is null then
        raise warning 'notify_vendor_review: missing Vault secret — skipping push';
        return new;
    end if;

    -- A vendor reviewing themselves (owner who also worked their own event) gets
    -- no push. The RPC makes this rare, but guard anyway.
    if new.reviewer_id = new.vendor_profile_id then
        return new;
    end if;

    perform net.http_post(
        url := v_project_url || '/functions/v1/shift-notify',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || v_service_key
        ),
        body := jsonb_build_object(
            'type', 'review_received',
            'review_id', new.id,
            'vendor_profile_id', new.vendor_profile_id,
            'rating', new.rating
        )
    );

    return new;
end;
$$;

comment on function public.notify_vendor_review()
    is 'AFTER INSERT trigger fn (E17): POSTs a new review to shift-notify '
       '(type review_received) for an alert push to the reviewed vendor. '
       'Vault-backed; no-ops with a warning if secrets are unset.';

drop trigger if exists trg_notify_vendor_review on public.vendor_reviews;
create trigger trg_notify_vendor_review
    after insert on public.vendor_reviews
    for each row
    when (new.deleted_at is null)
    execute function public.notify_vendor_review();
