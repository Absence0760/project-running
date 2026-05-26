-- audit/strava May 2026 High #2.
--
-- The token-refresh cron (Go worker `handler_token_refresh`) hits
-- the same expired-grant integration row every hour, forever:
--
--   * `strava.Refresh` returns 400 `invalid_grant` (user revoked at
--     Strava's end) or 401 (refresh token aged out).
--   * `refreshOne` logs + skips.
--   * The row's `token_expiry` is unchanged, so the next hourly
--     sweep re-lists the same row.
--   * Result: indefinite Strava-quota churn on bogus rows, and zero
--     UI signal that the user needs to reconnect.
--
-- Fix: a `disconnected_at` timestamptz column. The refresh handler
-- stamps it on 4xx (permanent failure shape), and the next sweep
-- filters out disconnected rows. The integration row stays around
-- so the UI can show "Strava is disconnected — Reconnect" and so
-- the eventual delete-account flow can still see the Vault material
-- it needs to deauthorise upstream.
--
-- Same column reused for the disconnect-flow we'll wire next:
-- user-initiated disconnect → stamp `disconnected_at` instead of
-- deleting the row, so the operator-side cleanup path is uniform.

alter table public.integrations
  add column if not exists disconnected_at timestamptz null;

alter table public.integrations
  add column if not exists disconnected_reason text null;

comment on column public.integrations.disconnected_at is
  'Set when the upstream OAuth grant becomes unusable (refresh '
  'returned 4xx) or when the user manually disconnects. The row is '
  'kept rather than deleted so (a) the UI can prompt Reconnect, '
  '(b) the audit log preserves the connection history. NULL means '
  'the integration is live; non-NULL means do not attempt to use '
  'the stored tokens. /audit/strava May 2026 High #2.';

comment on column public.integrations.disconnected_reason is
  'One of: invalid_grant, unauthorized, user_initiated. Free-text '
  'short tag so an operator scanning the table can spot the dominant '
  'failure mode without parsing the access logs.';

-- The "list expiring tokens" query the worker runs filters out
-- already-disconnected rows. This is the only schema-level
-- enforcement; the query itself lives in
-- apps/job_worker/internal/supabase.go (FetchExpiringStravaIntegrations)
-- and gets a `and disconnected_at is null` clause in the same commit.

-- No backfill: existing rows have NULL, which == live. The next
-- legitimate refresh either succeeds (no change) or 4xx-fails
-- (gets stamped + dropped from the sweep).
