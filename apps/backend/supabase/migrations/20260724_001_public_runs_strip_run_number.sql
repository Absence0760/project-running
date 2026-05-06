-- Preemptively strip `metadata.run_number` from `public_runs`.
--
-- `docs/metadata.md` documents `run_number` as a parkrun attendance
-- counter, classified owner-only, with the note "stripped from
-- public_runs in the same migration that lands the writer." Audit
-- pass 3 found no current writer in source — but also no strip in
-- the view. The covenant is documented but not enforced.
--
-- Add the strip preemptively so a future PR that wires the parkrun
-- scraper to write `run_number` doesn't have to remember to also
-- update the view in lockstep. The seed assertion already covers
-- the existing strip list; this entry will be additive.

create or replace view public_runs as
select
  r.id,
  r.user_id,
  r.started_at,
  r.duration_s,
  r.distance_m,
  r.source,
  r.is_public,
  r.track_url,
  r.created_at,
  r.updated_at,
  case when is_public_route_by_id(r.route_id) then r.route_id else null end as route_id,
  case when is_public_event_by_id(r.event_id) then r.event_id else null end as event_id,
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
    -- Pass-3 preemptive: parkrun attendance counter (no writer yet).
    - 'run_number'
    as metadata
from runs r
where r.is_public = true;

grant select on public_runs to anon, authenticated;
