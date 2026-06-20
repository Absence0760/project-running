-- Race calendar + results import (parity backlog #10, race_calendar.md).
--
-- Two pieces:
--   1. race_listings — the discoverable, public race calendar (one row per
--      real-world race), crowd-submittable + provider-synced. Mirrors the
--      clubs.location_point + search_public_events_geo proximity precedent.
--   2. runs.race_listing_id — links a recorded/imported run back to the
--      calendar entry it matched (mirrors runs.event_id). The imported result
--      itself is NOT a parallel table: it is written onto a runs row with
--      source='race' (already in the runs.source CHECK, 20260505_001) carrying
--      the owner-only race metadata keys. This reuses the per-user external_id
--      dedup index + the public_runs strip already built.
--
-- This migration also extends the public_runs strip to the three new race
-- metadata keys this feature's importer writes (gun_time / age_group_place /
-- age_group); the original four (race_name / bib / overall_place / chip_time)
-- were stripped by 20260714_001 and the column-promoted view 20261207_001.

-- ── race_listings (the calendar) ────────────────────────────────────────────
create table race_listings (
  id               uuid primary key default gen_random_uuid(),
  provider         text not null,
  provider_race_id text,
  name             text not null,
  race_date        date not null,
  distance_m       integer,
  location_label   text,
  location_point   geography(Point, 4326),
  entry_url        text,
  results_url      text,
  submitted_by     uuid references auth.users on delete set null,
  is_verified      boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

alter table race_listings add constraint race_listings_provider_check
  check (provider in ('runsignup', 'parkrun', 'manual', 'chronotrack', 'raceresult', 'ultrasignup'));
alter table race_listings add constraint race_listings_entry_url_scheme_check
  check (entry_url is null or entry_url ~* '^https?://');
alter table race_listings add constraint race_listings_results_url_scheme_check
  check (results_url is null or results_url ~* '^https?://');

-- One listing per provider race; manual listings (provider_race_id null) are
-- not globally unique — loose dedup on (name, date) is a client/import concern.
create unique index race_listings_provider_uniq
  on race_listings (provider, provider_race_id) where provider_race_id is not null;
create index race_listings_date_idx on race_listings (race_date);
create index race_listings_location_gist on race_listings using gist (location_point);

create extension if not exists pg_trgm with schema extensions;
create index race_listings_name_trgm
  on race_listings using gin (name extensions.gin_trgm_ops);

alter table race_listings enable row level security;

-- A race calendar is public discovery data — readable by anyone, incl. anon.
create policy "race listings readable by all"
  on race_listings for select using (true);

-- Authenticated users may submit a listing. is_verified is forced false on a
-- user INSERT by the trigger below so a submitter can't masquerade a crowd
-- listing as provider/admin-verified.
create policy "users submit race listings"
  on race_listings for insert to authenticated
  with check (submitted_by = auth.uid());

-- Submitter may edit their own UNVERIFIED listing; once verified it locks.
create policy "submitters edit own unverified listings"
  on race_listings for update to authenticated
  using (submitted_by = auth.uid() and is_verified = false)
  with check (submitted_by = auth.uid() and is_verified = false);

-- Force is_verified=false on any non-service-role write so a user can neither
-- self-verify on INSERT nor flip the flag on UPDATE. service_role (the import
-- EF + admin tooling) is the only writer that may set is_verified=true.
create or replace function force_unverified_listing()
  returns trigger language plpgsql security invoker as $$
begin
  if current_setting('role', true) is distinct from 'service_role'
     and (select auth.role()) is distinct from 'service_role' then
    new.is_verified := false;
  end if;
  return new;
end;
$$;

create trigger race_listings_force_unverified
  before insert or update on race_listings
  for each row execute function force_unverified_listing();

-- ── runs linkage ────────────────────────────────────────────────────────────
alter table runs add column race_listing_id uuid references race_listings on delete set null;
create index runs_race_listing_idx on runs (race_listing_id) where race_listing_id is not null;

-- ── search_race_listings RPC ────────────────────────────────────────────────
-- Proximity + soonest-first race discovery. Mirrors search_public_events_geo
-- (20270112_001): a `center` CTE, ST_DWithin radius gate, distance-ascending
-- order with a soonest-first fallback. security invoker, public-scoped — the
-- select policy above already permits anon reads, so this adds no exposure.
-- p_distance buckets the nominal distance_m into race-distance bands.
create or replace function search_race_listings(
  p_query      text default null,
  p_distance   text default null,             -- '5k' | '10k' | 'half' | 'marathon' | 'ultra'
  p_from       date default null,
  p_to         date default null,
  p_center_lng double precision default null,
  p_center_lat double precision default null,
  p_radius_m   double precision default 50000,
  p_limit      int  default 60
) returns table (
  id               uuid,
  provider         text,
  provider_race_id text,
  name             text,
  race_date        date,
  distance_m       integer,
  location_label   text,
  entry_url        text,
  results_url      text,
  is_verified      boolean,
  distance_m_away  double precision
) language sql stable security invoker as $$
  with center as (
    select case
      when p_center_lng is not null and p_center_lat is not null
      then ST_SetSRID(ST_MakePoint(p_center_lng, p_center_lat), 4326)::geography
    end as pt
  )
  select
    l.id,
    l.provider,
    l.provider_race_id,
    l.name,
    l.race_date,
    l.distance_m,
    l.location_label,
    l.entry_url,
    l.results_url,
    l.is_verified,
    case when center.pt is not null and l.location_point is not null
      then ST_Distance(l.location_point, center.pt)
      else null
    end as distance_m_away
  from race_listings l
  cross join center
  where
    -- Default to upcoming races; an explicit from/to window overrides.
    (p_from is not null or p_to is not null or l.race_date >= current_date)
    and (p_from is null or l.race_date >= p_from)
    and (p_to is null or l.race_date <= p_to)
    and (
      p_query is null
      or l.name ilike '%' || p_query || '%'
    )
    and (
      p_distance is null
      or (p_distance = '5k'       and l.distance_m between 4500 and 5500)
      or (p_distance = '10k'      and l.distance_m between 9000 and 11000)
      or (p_distance = 'half'     and l.distance_m between 20000 and 22000)
      or (p_distance = 'marathon' and l.distance_m between 41000 and 43000)
      or (p_distance = 'ultra'    and l.distance_m > 43000)
    )
    and (
      center.pt is null
      or (
        l.location_point is not null
        and ST_DWithin(l.location_point, center.pt, p_radius_m)
      )
    )
  order by
    case when center.pt is not null and l.location_point is not null
      then ST_Distance(l.location_point, center.pt)
      else null
    end asc nulls last,
    l.race_date asc,
    l.created_at desc
  limit greatest(1, least(p_limit, 200));
$$;

grant execute on function search_race_listings(
  text, text, date, date, double precision, double precision, double precision, int
) to authenticated, anon;

-- ── public_runs: add race_listing_id pass-through + strip new race keys ──────
-- race_listing_id is non-sensitive (it links only to a PUBLIC calendar row),
-- so it passes through. The three new owner-only race metadata keys this
-- feature writes are added to the strip list; the original four + the rest of
-- the denylist are carried forward verbatim from 20261207_001 (a bare CREATE
-- OR REPLACE here would otherwise silently drop the column-list change).
drop view if exists public_runs;

create view public_runs as
select
  r.id,
  r.user_id,
  r.started_at,
  r.duration_s,
  r.distance_m,
  r.source,
  r.activity_type,
  r.is_dnf,
  r.is_public,
  r.created_at,
  case when is_public_route_by_id(r.route_id) then r.route_id else null end as route_id,
  case when is_public_event_by_id(r.event_id) then r.event_id else null end as event_id,
  r.race_listing_id,
  (r.track_url is not null) as has_track,
  coalesce(r.metadata, '{}'::jsonb)
    - 'strava_id'
    - 'garmin_id'
    - 'imported_from'
    - 'imported_at'
    - 'health_connect_type'
    - 'strava_activity_type'
    - 'source_file'
    - 'max_bpm'
    - 'plan_workout_id'
    - 'workout_step_results'
    - 'workout_adherence'
    - 'last_modified_at'
    - 'recovered_from_crash'
    - 'in_progress_saved_at'
    - 'in_progress'
    - 'manual_entry'
    - 'indoor_estimated'
    - 'distance_source'
    - 'race_name'
    - 'bib'
    - 'overall_place'
    - 'chip_time'
    - 'gun_time'
    - 'age_group_place'
    - 'age_group'
    - 'perceived_effort'
    - 'run_number'
    as metadata
from runs r
where r.is_public = true;

grant select on public_runs to anon, authenticated;
