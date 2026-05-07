-- Redo of the column-level grant lockdowns from
-- `20260801_001_clubs_invite_token_lockdown.sql` and
-- `20260806_001_events_meet_point_authenticated_revoke.sql`,
-- which were reverted in `20260817_001` after CI caught them
-- breaking every web + mobile `select('*')` read on `clubs` and
-- `events`. The reverts unblocked CI; this migration re-applies
-- the lockdown alongside the call-site fix that 20260801_001 and
-- 20260806_001 forgot to land.
--
-- Why column-level grants are the right shape (and the redacted-
-- view alternative isn't):
--
--   * race_sessions_redacted (20260813_001) is `security_invoker = on`
--     and runs as the caller. A redacted view that uses
--     `case when is_club_admin(id) then invite_token else null end`
--     evaluates the column reference under invoker permissions —
--     so revoking SELECT on `invite_token` from authenticated would
--     make the case-when itself raise 42501. That pattern works
--     for race_sessions because no column was ever revoked there;
--     it doesn't compose with column-level lockdowns.
--   * A `security_invoker = off` view (the public_runs / public_routes
--     pattern) runs as owner and would let the case-when read
--     `invite_token` without invoker grants. But it bypasses RLS on
--     the base table, so the view body must duplicate the visibility
--     predicate (`is_public OR owner_id = auth.uid() OR
--     is_club_member(...)`) — and PostgREST resource embedding
--     (`event_attendees(events(...))`) targets the base table by FK,
--     not the view. Routing every read site through the view is a
--     much bigger refactor than enumerating columns at the call
--     sites.
--
-- The chosen shape: column-level grants on the base table + every
-- read site enumerates columns explicitly. This is enforced going
-- forward by `architecture_guards_test.dart` (mobile) and
-- `apps/web/tests-e2e/cross-cutting/select-star-discipline.spec.ts`
-- (web), which scan source for `from('clubs').select('*')` and
-- `from('events').select('*')` and fail. New columns added to
-- either table are deny-by-default for anon + authenticated; if a
-- future column is meant to be cross-user readable, this migration
-- must be amended.
--
-- The base RLS policies on both tables are unchanged — row
-- visibility still flows through the existing
-- "public clubs are readable by anyone" / "events readable with
-- their club" policies. This migration only narrows which columns
-- the role can SELECT.

-- ─── clubs ─── (mirror of 20260801_001)
revoke select on clubs from authenticated, anon;

grant select (
  id,
  owner_id,
  name,
  slug,
  description,
  avatar_url,
  location_label,
  is_public,
  join_policy,
  created_at,
  updated_at
) on clubs to authenticated, anon;

-- ─── events ─── (mirror of 20260723_001 + 20260806_001)
revoke select on events from authenticated, anon;

grant select (
  id,
  club_id,
  title,
  description,
  starts_at,
  duration_min,
  meet_label,
  route_id,
  distance_m,
  pace_target_sec,
  capacity,
  created_by,
  created_at,
  updated_at,
  recurrence_freq,
  recurrence_byday,
  recurrence_until,
  recurrence_count
) on events to authenticated, anon;
