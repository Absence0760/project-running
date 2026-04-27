-- Revoke public read on mv_weekly_mileage.
--
-- Materialized views can't have RLS in PostgreSQL, but Supabase's
-- default role grants `select on all tables in schema public` to
-- `anon` and `authenticated` — and "all tables" includes matviews.
-- Without this revoke, anyone (including unauthenticated callers via
-- the PostgREST anon endpoint) can dump every user's weekly mileage
-- history via /rest/v1/mv_weekly_mileage.
--
-- The matview has zero callers in the app today (provisioned in
-- 20260407 ahead of need; see docs/backend_scaling.md). The
-- canonical client read path is the `weekly_mileage()` SQL function
-- in 20260406, which already gates on `auth.uid()`. Background
-- refresh jobs using the service role are unaffected — service-role
-- grants don't go through PUBLIC.

revoke select on mv_weekly_mileage from anon, authenticated;
