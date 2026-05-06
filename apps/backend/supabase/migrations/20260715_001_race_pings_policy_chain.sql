-- Tighten the `race_pings` SELECT policy to mirror the parent
-- `race_sessions` visibility chain.
--
-- Original policy (`20260425_001_race_sessions.sql:109-117`) checked
-- only that a `race_sessions` row exists for the matching
-- `(event_id, instance_start)` PK. That gate is satisfied for ANY
-- caller who knows or can guess the composite key — it does NOT
-- chain through `events → clubs` to the club-visibility predicate
-- the sibling `race_sessions_visible_when_event_is` policy applies.
--
-- Net effect: an authenticated user who obtains a `(event_id,
-- instance_start)` value from any source — e.g. read off a public
-- club's events list, then guess instance_start by trying recent
-- timestamps — could read live lat/lng pings for any race that
-- shares those coordinates, including private-club races they are
-- not a member of. Privacy-zone runners are protected by the
-- `race_pings_drop_in_zone` BEFORE-INSERT trigger
-- (`20260704_001`), but non-zone-protected coordinates (the
-- runner's actual position outside their home/work zones) leak.
--
-- Fix: replace the EXISTS clause with the same join through
-- `events → clubs` plus the `is_public OR owner OR member`
-- predicate that `race_sessions_visible_when_event_is` uses.

drop policy if exists race_pings_visible_when_race_is on race_pings;

-- `events.club_id` is NOT NULL (20260416_001), so the LEFT JOIN
-- branch with `c.id is null` is unreachable. 20260519_001 already
-- cleaned up the same dead branch in race_sessions /
-- event_results — using a plain JOIN here for the same reason
-- (audit pass 3 caught the regression).
create policy race_pings_visible_when_race_is
  on race_pings for select
  using (
    exists (
      select 1
      from race_sessions rs
      join events e on e.id = rs.event_id
      join clubs c on c.id = e.club_id
      where rs.event_id = race_pings.event_id
        and rs.instance_start = race_pings.instance_start
        and (
          c.is_public = true
          or c.owner_id = auth.uid()
          or is_club_member(c.id)
        )
    )
  );
