-- Persona-hunt social-group #10: surface the event meetup point on the
-- event detail page (map pin + "Get directions" link).
--
-- `events.meet_lat` / `meet_lng` are column-revoked from anon AND
-- authenticated (migrations 20260723_001 + 20260806_001 + 20260818_001)
-- because a direct `select meet_lat,meet_lng from events` would let any
-- signed-in non-member scrape precise meeting coordinates for every
-- public-club event — including the corner case of an organiser using
-- their home address. The 20260806_001 migration explicitly prescribed
-- the unlock path: "gate it behind a SECURITY DEFINER RPC like
-- get_event_meet_point(uuid) keyed on is_club_member(events.club_id)".
-- This is that RPC.
--
-- Membership gate: only an active member of the event's club gets the
-- coordinates. Everyone else (including signed-in non-members and the
-- event's own anon viewers) gets no rows — the detail page then shows
-- only the text `meet_label`, exactly as before.

create or replace function get_event_meet_point(p_event_id uuid)
returns table (meet_lat double precision, meet_lng double precision)
language sql
security definer
set search_path = public
as $$
  select e.meet_lat, e.meet_lng
  from events e
  where e.id = p_event_id
    and e.meet_lat is not null
    and e.meet_lng is not null
    and is_club_member(e.club_id);
$$;

-- The membership check inside the function IS the authorization gate,
-- so EXECUTE is granted to both client roles: an anon (or non-member)
-- caller runs the body but `is_club_member` returns false → zero rows.
-- (Gating EXECUTE itself would force the permission-denied path, which
-- a logged-out viewer hitting the REST endpoint would trip on every
-- call — and is unnecessary once the row-level gate is in place.)
revoke all on function get_event_meet_point(uuid) from public;
grant execute on function get_event_meet_point(uuid) to anon, authenticated;

comment on function get_event_meet_point(uuid) is
  'Returns the meetup coordinates for an event only to active members '
  'of its club. The meet_lat/meet_lng columns are otherwise revoked '
  'from all client roles to prevent scraping precise meeting points '
  '(see migrations 20260723_001 / 20260806_001). Persona social-group #10.';
