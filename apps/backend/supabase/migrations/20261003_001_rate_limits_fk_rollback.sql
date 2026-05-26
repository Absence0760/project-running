-- Roll back the `rate_limits.user_id` → `auth.users` FK added in
-- migration 20260928_001_gdpr_dsar_closeouts.sql.
--
-- The FK aimed to close audit/gdpr May 2026 High #1 — "deleted
-- user's UUID survives in rate_limits for up to 24h post-deletion".
-- Implementation choice was ON DELETE CASCADE on the FK. That broke
-- four callers that legitimately insert synthetic UUIDs into the
-- same table:
--
--   * `apps/backend/supabase/functions/strava-webhook/index.ts`
--     uses `ipBucketKey(req)` (a SHA-256 → UUID hash of the
--     client IP) to rate-limit the anon webhook path. The hash
--     is NOT in `auth.users`, so the FK rejected every insert
--     with 23503 — the function then fell through to the
--     fail-closed branch and 503'd the whole webhook.
--   * `apps/backend/supabase/functions/clip-public-track/index.ts`
--     uses the same `ipBucketKey` pattern for the anon clip path.
--   * Future anon-path EFs that follow the documented pattern in
--     `_shared/rate_limit.ts:11-13` would silently break the same
--     way.
--
-- The audit-fix alternative was explicit drain in `delete-account`.
-- That's what we land now (commit pairs this migration with the
-- `delete-account/index.ts` drain). The 24h `cleanup_stale_rate_
-- limits` cron still applies as the long-tail sweep; the explicit
-- drain handles the per-deletion case.

alter table public.rate_limits
  drop constraint if exists rate_limits_user_id_fkey;

comment on table public.rate_limits is
  'Per-(user_id, bucket) sliding-window counters. user_id is NOT '
  'foreign-keyed to auth.users — the table also stores synthetic '
  'UUIDs from ipBucketKey() for anon webhook paths (strava-webhook, '
  'clip-public-track). The audit/gdpr-flagged "deleted user UUID '
  'survives 24h" gap is closed by the explicit drain in '
  'delete-account/index.ts (the immediate path) + the hourly '
  'cleanup_stale_rate_limits cron (the long tail).';
