-- Privacy-vs-safety carve-out for the race (event-leaderboard) live feed.
--
-- 20260704_001 installed a BEFORE-INSERT trigger that returns NULL for
-- any race ping whose coordinates fall inside one of the runner's
-- privacy zones, so an exact home/work point never reaches the
-- spectator leaderboard/map or the realtime feed anyone watching a
-- public-club race sees. That is the right default for a runner passing
-- through a zone mid-race.
--
-- But it has the same safety hole 20270121_001 closed for the solo
-- live-run feed: a runner who STOPS inside their own zone — collapses
-- injured, or never leaves the venue after starting — emits only in-zone
-- pings from that point on, every one of which is dropped. They vanish
-- from the leaderboard + any search precisely when a watcher (a race
-- director, a crew member, SAR) most needs a last-known position.
--
-- Carve-out (privacy-vs-safety): for an in-zone race ping, instead of
-- dropping it outright, retain the SINGLE most-recent in-zone ping per
-- runner-per-race-instance, but COARSENED — lat/lng rounded to 2 decimal
-- places (~1.1 km of latitude; less in longitude away from the equator)
-- via the shared `privacy_coarsen_coord` helper from 20270121_001. That
-- reads as "last seen near here", never the exact zone centre. The row
-- is flagged `coarse = true` so every downstream surface (spectator map,
-- leaderboard row) can label it and must never treat it as a precise
-- sample. Older in-zone coarse pings for the same runner in the same
-- race instance are deleted before the new one lands, so the feed
-- carries at most one coarse last-seen point per runner that always
-- moves forward to the latest stop.
--
-- The per-runner scope here is (event_id, instance_start, user_id) — the
-- race-ping analogue of live_run_pings' per-run `run_id`. distance_m /
-- elapsed_s / bpm are left untouched: they are the leaderboard's ranking
-- values and carry no positional precision (unlike live_run_pings' `ele`,
-- which the solo trigger strips because altitude helps pinpoint a home).
--
-- Fail-safe: only the precise lat/lng is ever coarsened-and-kept; if any
-- step is ambiguous (no zones, unreadable prefs) we fall back to the
-- prior behaviour — pass out-of-zone pings through untouched — so the
-- failure mode is "less location leaked", never "exact home point
-- broadcast". Mirrors 20270121_001 semantics exactly.

alter table race_pings
  add column if not exists coarse boolean not null default false;

create or replace function race_pings_drop_in_zone()
returns trigger
language plpgsql
security definer
-- Need `extensions` on the search path so the call chain into
-- privacy_in_any_zone → privacy_distance_m → PostGIS st_distance /
-- st_makepoint resolves. Same shape as live_run_pings_drop_in_zone.
set search_path = public, extensions
as $$
declare
  v_zones jsonb;
begin
  select prefs->'privacy_zones' into v_zones
    from user_settings where user_id = new.user_id;

  if v_zones is null
     or jsonb_typeof(v_zones) <> 'array'
     or jsonb_array_length(v_zones) = 0
  then
    return new;
  end if;

  if privacy_in_any_zone(new.lat, new.lng, v_zones) then
    -- In-zone: keep ONLY a single coarsened last-seen ping per runner in
    -- this race instance for the safety feed. Drop any prior coarse
    -- last-seen so it never accumulates and always advances to the
    -- newest stop, then coarsen + flag this row.
    delete from race_pings
     where event_id = new.event_id
       and instance_start = new.instance_start
       and user_id = new.user_id
       and coarse = true;

    new.lat := privacy_coarsen_coord(new.lat);
    new.lng := privacy_coarsen_coord(new.lng);
    new.coarse := true;
    return new;
  end if;

  return new;
end;
$$;
