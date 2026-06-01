-- audit-findings 2026-05-30 Medium: the four club/event membership
-- oracles — `is_club_member`, `is_club_admin`, `is_event_organiser`,
-- `is_race_director` — are SECURITY DEFINER helpers living in the
-- `public` schema, so PostgREST exposes each as an anon-callable RPC.
-- Anyone can hit `POST /rest/v1/rpc/is_club_member` (etc.) with a
-- club/event UUID and read back `true`/`false` — a membership/role
-- oracle for any (caller, club) pair, even on private clubs. The
-- information isn't otherwise reachable by an outsider, so this is a
-- genuine disclosure surface, not just a convenience duplicate.
--
-- Same remedy as `is_run_visible_to` (migration 20260812_001): move
-- the functions into the `private` schema, which PostgREST does not
-- expose (Supabase's `db_schemas = public, graphql_public, storage`
-- — `private` is outside that list). RLS policies and SECURITY
-- DEFINER callers keep working; the anonymous RPC oracle disappears
-- (`POST /rest/v1/rpc/is_club_member` → 404).
--
-- Method note — why `ALTER FUNCTION ... SET SCHEMA` and not the
-- recreate-every-policy approach the 20260812_001 migration used:
-- these four oracles are referenced by ~30 RLS policies across ~33
-- migration files (`is_club_member` alone in 28). `ALTER FUNCTION
-- SET SCHEMA` preserves the function's OID, and Postgres records RLS
-- policy → function dependencies by OID, so every dependent policy's
-- stored expression is rewritten to the `private.`-qualified name
-- automatically and atomically — no policy needs re-emitting, which
-- eliminates the transcription-error class entirely (verified: a
-- policy reading `is_club_member(club_id)` reads
-- `private.is_club_member(club_id)` immediately after the move). The
-- SECURITY DEFINER *callers* (`approve_event_result`,
-- `decide_event_result_claim`, `clone_plan_template`) re-parse their
-- bodies by name at execution time rather than by OID, so they don't
-- follow the move — they get `private` appended to their search_path
-- below so their unqualified oracle calls resolve to the moved
-- functions without re-emitting their (long) bodies.

create schema if not exists private;

-- Idempotent re-statement of the grant/comment posture from
-- 20260812_001 in case this lands before it in a fresh-rebuild order
-- (it won't, given filename ordering, but cheap insurance).
grant usage on schema private to anon, authenticated, service_role;

-- ───────── Move the four oracles into `private` ─────────
-- Each takes a single `target_club uuid` argument. SET SCHEMA keeps
-- the body, SECURITY DEFINER posture, search_path, and OID intact.
alter function public.is_club_member(uuid) set schema private;
alter function public.is_club_admin(uuid) set schema private;
alter function public.is_event_organiser(uuid) set schema private;
alter function public.is_race_director(uuid) set schema private;

-- Tighten the execute grants to match the `is_run_visible_to`
-- hygiene: drop the implicit PUBLIC grant the functions carried, and
-- grant only the roles that evaluate RLS (anon + authenticated) plus
-- service_role. The qualified call from a policy bypasses search_path
-- entirely; these grants are what let the anon/authenticated role
-- actually execute the function during policy evaluation.
revoke execute on function private.is_club_member(uuid) from public;
revoke execute on function private.is_club_admin(uuid) from public;
revoke execute on function private.is_event_organiser(uuid) from public;
revoke execute on function private.is_race_director(uuid) from public;

grant execute on function private.is_club_member(uuid)
  to anon, authenticated, service_role;
grant execute on function private.is_club_admin(uuid)
  to anon, authenticated, service_role;
grant execute on function private.is_event_organiser(uuid)
  to anon, authenticated, service_role;
grant execute on function private.is_race_director(uuid)
  to anon, authenticated, service_role;

-- ───────── Fix the SECURITY DEFINER callers ─────────
-- These three definer functions call the oracles by unqualified name
-- from `set search_path = public`. With the oracles gone from public,
-- those calls would fail to resolve. Append `private` to each
-- function's search_path so the unqualified name falls through to the
-- moved function. Safe against search-path privilege escalation:
-- `private` is owned by the migration role and anon/authenticated
-- hold only USAGE (no CREATE), so a caller can't plant a shadowing
-- object there.
--   approve_event_result        → is_race_director
--   decide_event_result_claim   → is_event_organiser
--   clone_plan_template         → is_club_member
--   claim_event_result          → is_club_member
--   clip_route_for_viewer       → is_club_member
--   get_club_invite_token       → is_club_admin
--   get_event_meet_point        → is_club_member
--   segment_leaderboard_tiered  → is_club_member
-- Each ALTER preserves the function's existing search_path entries and
-- only appends `private` (clip_route_for_viewer keeps `extensions`).
alter function approve_event_result(uuid, timestamptz, uuid, boolean)
  set search_path = public, private;
alter function decide_event_result_claim(uuid, boolean)
  set search_path = public, private;
alter function clone_plan_template(uuid, date)
  set search_path = public, private;
alter function claim_event_result(uuid)
  set search_path = public, private;
alter function clip_route_for_viewer(uuid)
  set search_path = public, extensions, private;
alter function get_club_invite_token(uuid)
  set search_path = public, private;
alter function get_event_meet_point(uuid)
  set search_path = public, private;
alter function segment_leaderboard_tiered(uuid, text, text, integer, uuid)
  set search_path = public, private;
