-- Privacy-vs-safety carve-out for the live-run spectator/SAR feed.
--
-- 20260618_001 (live_run_pings) and 20260704_001 (race_pings) install
-- BEFORE-INSERT triggers that return NULL for any ping whose
-- coordinates fall inside one of the runner's privacy zones, so the
-- exact home/work point never reaches the realtime feed or anyone
-- watching it. That is the right default for a runner passing through a
-- zone mid-run.
--
-- But it has a safety hole: a runner who STOPS inside their own zone —
-- collapses injured at home, or never leaves the hotel after starting —
-- emits only in-zone pings from that point on, every one of which is
-- dropped. They vanish entirely from the spectator + search-and-rescue
-- feed precisely when a watcher most needs a last-known position.
--
-- Carve-out (privacy-vs-safety): for an in-zone ping, instead of
-- dropping it outright, retain the SINGLE most-recent in-zone ping per
-- run, but COARSENED — lat/lng rounded to 2 decimal places (~1.1 km of
-- latitude; less in longitude away from the equator). That reads as
-- "last seen near here", never the exact zone centre. The row is
-- flagged `coarse = true` so every downstream surface (spectator map,
-- SAR view, leaderboard) can label it and must never treat it as a
-- precise sample. Older in-zone coarse pings for the run are deleted
-- before the new one lands, so the feed carries at most one coarse
-- last-seen point that always moves forward to the latest stop.
--
-- Fail-safe: only the precise lat/lng is ever coarsened-and-kept; if any
-- step is ambiguous (no zones, unreadable prefs) we fall back to the
-- prior behaviour — drop precise in-zone pings / pass out-of-zone pings
-- through untouched — so the failure mode is "less location leaked",
-- never "exact home point broadcast".
--
-- The 2-dp grid is a deliberate floor: it is coarse enough that the
-- coarsened point cannot be back-solved to the zone centre, yet useful
-- enough for a ground search to start in the right ~1 km cell. This is
-- the item that most needs the human /audit/privacy-zones sign-off
-- before prod — see decisions §33 + the carve-out review note.

alter table live_run_pings
  add column if not exists coarse boolean not null default false;

-- ~2-dp grid. round(x::numeric, 2) → ~0.01° cell. Kept as a SQL helper
-- so the trigger body and any downstream check share one definition of
-- "coarse".
create or replace function privacy_coarsen_coord(coord double precision)
returns double precision
language sql
immutable
parallel safe
as $$
  select round(coord::numeric, 2)::double precision;
$$;

create or replace function live_run_pings_drop_in_zone()
returns trigger
language plpgsql
security definer
-- Need `extensions` on the search path so the call chain into
-- privacy_in_any_zone → privacy_distance_m → PostGIS st_distance /
-- st_makepoint resolves. The existing privacy_distance_m doesn't
-- pin its own path, so it inherits ours; pinning to just `public`
-- (the usual safe default) trips '42704: type "geography" does not
-- exist' under SECURITY DEFINER context.
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
    -- In-zone: keep ONLY a single coarsened last-seen ping per run for
    -- SAR. Drop any prior coarse last-seen so it never accumulates and
    -- always advances to the newest stop, then coarsen + flag this row.
    delete from live_run_pings
     where run_id = new.run_id
       and coarse = true;

    new.lat := privacy_coarsen_coord(new.lat);
    new.lng := privacy_coarsen_coord(new.lng);
    new.ele := null;
    new.coarse := true;
    return new;
  end if;

  return new;
end;
$$;
