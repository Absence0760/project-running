-- Persona-hunt Round 5 (very-social, Critical): the feed + profile map
-- thumbnails went permanently missing for every run. `SocialFeed` and the
-- `/u/[id]` run grid / activity list gate the map preview on `track_url`,
-- but 20260924_001 dropped `track_url` from `public_runs` for defence-in-
-- depth, so the gate is dead for every public-run surface.
--
-- Re-expose a SAFE signal — a boolean `has_track` derived from
-- `track_url IS NOT NULL`. This reveals only whether a GPS trace exists
-- (already implied by a public run), never the `{user_id}/{run_id}.json.gz`
-- Storage path. The path is what 20260924_001 protected; a boolean cannot
-- reconstruct it, so the audit's concern (a future Storage-RLS loosening
-- re-opening direct download from a leaked path) does not re-apply. The
-- clip-public-track Edge Function still derives the path from user_id +
-- run_id itself — non-owner thumbnails fetch the clipped trace through it.
--
-- DROP + CREATE because Postgres rejects column addition that reorders /
-- changes a view's output via `create or replace view` once the column
-- list differs (42P16).

drop view if exists public_runs;

create view public_runs as
select
  r.id,
  r.user_id,
  r.started_at,
  r.duration_s,
  r.distance_m,
  r.source,
  r.is_public,
  r.created_at,
  case when is_public_route_by_id(r.route_id) then r.route_id else null end as route_id,
  case when is_public_event_by_id(r.event_id) then r.event_id else null end as event_id,
  -- Boolean existence signal only — never the Storage path itself.
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
    - 'perceived_effort'
    - 'run_number'
    as metadata
from runs r
where r.is_public = true;

grant select on public_runs to anon, authenticated;
