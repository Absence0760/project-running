-- audit-findings 2026-05-30 High [security/rls] — `app_quota` shipped
-- without RLS (20261007_001), so any authenticated caller could read,
-- inflate, or reset the app-wide Strava quota counter directly over
-- PostgREST — a one-row write could trip the soft floor and make the
-- whole app back off from Strava, or zero it out to blow the real
-- Strava limit and get the app suspended.
--
-- The counter is only ever touched by `try_consume_strava_quota()`
-- (SECURITY DEFINER, service_role-only) and the cleanup cron, both of
-- which bypass RLS by design. Mirror the `rate_limits` lockdown
-- (20260604_001): enable RLS with no policies + revoke direct grants,
-- so anyone hitting the table over REST sees zero rows and can write
-- nothing.
revoke all on table public.app_quota from anon, authenticated;
alter table public.app_quota enable row level security;

-- The gate RPC was meant to be service_role-only, but `revoke ... from
-- public` in 20261007_001 didn't cover it: Supabase's default
-- privileges grant EXECUTE on every new function to `anon` +
-- `authenticated`, so any caller (even anon) could call
-- `try_consume_strava_quota()` and inflate the counter to DoS the
-- app's own Strava access. Revoke those explicit grants — the Go
-- worker + Edge Functions use the service key.
revoke all on function try_consume_strava_quota(integer, integer) from anon, authenticated;
