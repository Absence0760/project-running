-- /audit/all Medium: `events.meet_lat` / `meet_lng` are still
-- readable by ANY authenticated user (not just club members) for
-- public-club events. The 20260723_001 migration revoked anon, but
-- the table-level grant for `authenticated` was left intact, so a
-- signed-in non-member of a public club can scrape every event's
-- precise meeting-point coordinates — including the corner case
-- where an organiser uses their home address as the meet point.
--
-- The earlier migration's comment acknowledged this gap explicitly
-- ("Authenticated callers... still see every column. Narrowing
-- further would require a SECURITY DEFINER RPC and refactoring every
-- event-detail render.") — re-checked here: across the whole repo,
-- NO render path reads `meet_lat` / `meet_lng`. Only `meet_label` is
-- displayed; the numeric pair is written by `createEvent` /
-- `updateEvent` and stored for a future map-pin feature that hasn't
-- shipped. The wire-format leak is therefore a pure data exposure
-- with no client-side dependency to refactor — extending the same
-- revoke shape to `authenticated` is safe.
--
-- If a future feature needs the coordinates on the event detail
-- page, gate it behind a SECURITY DEFINER RPC like
-- `get_event_meet_point(uuid)` keyed on `is_club_member(events.club_id)`.

revoke select on events from authenticated;

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
) on events to authenticated;
