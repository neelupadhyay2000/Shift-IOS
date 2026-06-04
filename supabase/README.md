# SHIFT – Supabase Migrations

## Prerequisites

```bash
brew install supabase/tap/supabase
supabase login        # opens browser; one-time setup
```

## Project refs

| Environment | Ref | URL |
|---|---|---|
| Dev  | `wrhrpyinkcopqsibmkrf` | https://wrhrpyinkcopqsibmkrf.supabase.co |
| Prod | `jakrlxnvdnsunrnspwnt` | https://jakrlxnvdnsunrnspwnt.supabase.co |

## Daily workflow

```bash
# Link to dev (one-time per machine; prompts for DB password)
supabase link --project-ref wrhrpyinkcopqsibmkrf

# Create a new migration
supabase migration new <descriptive_name>
# → writes supabase/migrations/<timestamp>_<name>.sql

# Apply pending migrations to dev
supabase db push

# Apply to prod (re-link first)
supabase link --project-ref jakrlxnvdnsunrnspwnt
supabase db push
supabase link --project-ref wrhrpyinkcopqsibmkrf   # switch back to dev
```

## Rules

- Every schema change **must** go through a migration file — no manual SQL in the dashboard.
- Migration files are **append-only**; never edit a file that has already been applied.
- Secrets (DB password, service-role key) are never committed — use `supabase login` + the password prompt.
