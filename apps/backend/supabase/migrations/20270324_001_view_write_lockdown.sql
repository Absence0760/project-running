-- Close an RLS bypass through the public/redacted VIEWS (found 2026-07-03
-- while verifying the 20270320_001 redaction; predates it).
--
-- Supabase's default privileges grant anon/authenticated FULL table
-- privileges (insert/update/delete/...) on every object created in the public
-- schema. For TABLES that is safe — RLS gates the rows. For VIEWS it is not:
-- a simple single-table view is AUTO-UPDATABLE, and a write through a view is
-- authorised against the base table as the VIEW OWNER (postgres), which
-- bypasses RLS entirely. Verified live: an anon PostgREST
-- `POST /rest/v1/public_race_listings` inserted a race_listings row despite
-- the base table's authenticated-only INSERT policy — and the same shape
-- reaches runs / gym_workouts / food_log / user_profiles / race_sessions /
-- event_results through their redacted views (public_runs even projects
-- user_id, so a forged row can be planted under any user).
--
-- Every view's defining migration only ever intended `grant select`; the
-- write bits arrived silently from the default privileges at CREATE time.
-- Reset each view to exactly its documented read audience. The pgtap suite
-- gains a catch-all pin (view_write_privileges_test.sql) so a FUTURE view
-- created without this reset fails CI instead of shipping writable.

revoke all on public.activities from public, anon, authenticated;
grant select on public.activities to authenticated;

revoke all on public.event_results_redacted from public, anon, authenticated;
grant select on public.event_results_redacted to anon, authenticated;

revoke all on public.gear_with_distance from public, anon, authenticated;
grant select on public.gear_with_distance to authenticated;

revoke all on public.public_food_log from public, anon, authenticated;
grant select on public.public_food_log to anon, authenticated;

revoke all on public.public_gym_routines from public, anon, authenticated;
grant select on public.public_gym_routines to authenticated;

revoke all on public.public_gym_workouts from public, anon, authenticated;
grant select on public.public_gym_workouts to anon, authenticated;

revoke all on public.public_profiles from public, anon, authenticated;
grant select on public.public_profiles to authenticated;

revoke all on public.public_race_listings from public, anon, authenticated;
grant select on public.public_race_listings to anon, authenticated;

revoke all on public.public_routes from public, anon, authenticated;
grant select on public.public_routes to anon, authenticated;

revoke all on public.public_runs from public, anon, authenticated;
grant select on public.public_runs to anon, authenticated;

revoke all on public.race_sessions_redacted from public, anon, authenticated;
grant select on public.race_sessions_redacted to anon, authenticated;
