-- Restrict `events.meet_lat` / `events.meet_lng` to authenticated
-- readers only.
--
-- Audit pass 3 finding (deferred from pass 2): the events table's
-- SELECT policy lets anon read public-club events. The two
-- numeric-coordinate columns leak precise meeting-point coordinates
-- to anyone hitting `/rest/v1/events?club_id=eq.<public_club_id>`,
-- including the corner case where an organiser uses their home
-- address as the meet point.
--
-- Implementation note: column-level REVOKE is a no-op when the role
-- still has table-level SELECT (Postgres uses the broadest grant).
-- The earlier shape of this migration was just `revoke select
-- (meet_lat, meet_lng) on events from anon;` — column-level revoke
-- under a still-present table-level grant — and behaved as a no-op
-- (caught by `rls_events_meet_point_test.sql` after it was added).
-- The correct shape is: revoke the table-level SELECT for anon, then
-- re-grant SELECT only on the safe columns. New columns added to
-- this table will be deny-by-default for anon — that is the intended
-- behaviour; if a future column is meant to be anon-readable, this
-- migration must be amended.
--
-- Authenticated callers (any signed-in user, not just members) still
-- see every column. Narrowing further would require a SECURITY
-- DEFINER RPC and refactoring every event-detail render.
--
-- Anon-side cost: web `select('*')` on `events` would have erred
-- 42501; the four caller sites in `apps/web/src/lib/data.ts` were
-- updated alongside this migration to enumerate the safe columns.

revoke select on events from anon;

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
) on events to anon;
