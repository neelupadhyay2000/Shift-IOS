-- Account deletion moved to the delete-account Edge Function.
--
-- The RPC failed in hosted Supabase: a platform protection trigger blocks
-- direct SQL deletes on storage tables ("Direct deletion from storage tables
-- is not allowed. Use the Storage API instead."), and it fires per statement,
-- so the function raised for every caller — even users with no voice memos.
-- The voice-memo cleanup, and with it the whole deletion, now runs through
-- the Storage + Auth admin APIs in supabase/functions/delete-account.
drop function if exists public.delete_account();
