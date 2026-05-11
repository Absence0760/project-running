-- Extend the `jobs.kind` CHECK allowlist to admit `strava_event`,
-- the kind enqueued by the Go service's Strava webhook endpoint
-- (`apps/job_worker/internal/stravahook/server.go`). The worker
-- handler (`apps/job_worker/internal/handler_strava_event.go`)
-- fetches the activity detail + streams from Strava, dedupes
-- against `metadata.strava_id`, and inserts a `runs` row — same
-- byte-for-byte shape as the existing `strava-webhook` Edge
-- Function it replaces.
--
-- Three-file rule from 20260822_001: a new kind requires the
-- migration + the Go dispatch case + the pgtap test (extended
-- in this same commit at
-- `apps/backend/supabase/tests/jobs_kind_allowlist_test.sql`).
-- Until all three land, the CHECK rejects inserts at 23514 so
-- the Go path can't silently drop events.
--
-- Existing data: there are no `strava_event` rows today (the
-- kind didn't exist before this commit), so no backfill is
-- needed.

alter table public.jobs
  drop constraint jobs_kind_chk;

alter table public.jobs
  add constraint jobs_kind_chk
  check (kind in ('map_match', 'token_refresh', 'strava_event'));
