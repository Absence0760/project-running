-- Close the shadow-hidden gap in the public-link helper functions
-- (audit/public-rows 2026-07-03). 20270218_001 added `shadow_hidden` to
-- clubs / routes / user_profiles and filtered every public/search/discovery
-- read path — but the three SECURITY DEFINER join helpers behind public_runs
-- / public_routes (`is_public_route_by_id`, `is_public_club_by_id`,
-- `is_public_event_by_id`) still answered on `is_public` alone, so a
-- shadow-hidden route or club stayed linkable (route_id / club_id / event_id
-- survived the existence-leak guard) on the public views. Re-emit all three
-- with the shadow filter; missing rows keep returning false.
--
-- is_public_event_by_id also gains the event-level `e.is_public` gate that
-- 20270113_001 added to is_event_visible after this helper was written: the
-- helper answers for EVERY viewer of a public run (anon included), so a
-- members-only event in a public club must not leak its id through
-- public_runs.event_id.

create or replace function is_public_route_by_id(p_route_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select is_public and not shadow_hidden from routes where id = p_route_id),
    false
  );
$$;

create or replace function is_public_club_by_id(p_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select is_public and not shadow_hidden from clubs where id = p_club_id),
    false
  );
$$;

create or replace function is_public_event_by_id(p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select c.is_public and not c.shadow_hidden and e.is_public
      from events e
      join clubs c on c.id = e.club_id
      where e.id = p_event_id
    ),
    false
  );
$$;
