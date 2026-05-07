-- /audit/all rls Medium: `approve_event_result` is SECURITY DEFINER,
-- granted to `authenticated` in 20260425_001 / 20260428_001 but with
-- no explicit `revoke from public, anon` first. In Supabase, every
-- new function in `public` schema gets an implicit
-- `grant execute to public` from the project-wide default, so the
-- targeted grant doesn't actually narrow execution — anon can hit
-- `POST /rest/v1/rpc/approve_event_result` too.
--
-- Same anon-callable-DEFINER pattern that 20260711_001 closed for
-- `is_route_visible_to`, `recompute_event_ranks`, etc. The function's
-- `is_race_director` body guard would still block an anon caller from
-- actually approving anything (they have no club membership), but a
-- DEFINER function callable by anyone is a defence-in-depth gap, and
-- the same `20260711_001` migration explicitly listed this kind of
-- function as needing the revoke pattern.

revoke execute on function approve_event_result(uuid, timestamptz, uuid, boolean) from public, anon;
grant execute on function approve_event_result(uuid, timestamptz, uuid, boolean) to authenticated;

-- The four club-membership / event-organiser predicates
-- (`is_club_admin`, `is_club_member`, `is_event_organiser`,
-- `is_race_director`) ARE callable by anon as RPC oracles, but
-- revoking would break anon RLS evaluation on `clubs`, `events`,
-- `event_attendees`, `club_posts` etc. — those tables' SELECT
-- policies inline-call the helpers, and Postgres evaluates the
-- policy in the caller's role, requiring EXECUTE permission.
-- Closing them properly needs the same `private`-schema move
-- that 20260812_001 applied to `is_run_visible_to`. Deferred
-- to a future pass; the disclosed information (membership
-- existence for a known UUID + caller pair) is bounded and is
-- already observable indirectly via the public/private clubs
-- read paths.
