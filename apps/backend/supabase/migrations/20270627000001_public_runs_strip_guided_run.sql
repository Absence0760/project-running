-- Strip metadata.guided_run_id from public_runs.
--
-- The key names which scripted coach workout a run was recorded under, and
-- the vocabulary is legible rather than opaque: `easy-30`, `tempo-builder-25`,
-- `first-timer-15`. It was first classified public-safe by analogy with
-- `sub_sport`, on the reasoning that a catalogue id carries no geographic,
-- identity or pace signal. That reading is backwards for this key on both
-- halves.
--
-- It is a statement about the RUNNER, not about the run's surface. `trail` and
-- `treadmill` describe where the feet landed; `first-timer-15` says the person
-- is a beginner, and says it in words any anonymous reader of the share page
-- understands without a lookup. And the comparison against `plan_workout_id`
-- runs the wrong way: that key is an opaque uuid disclosing nothing until it
-- is resolved against a table the reader cannot select from, and it is
-- stripped. Exposing the legible label while hiding the opaque one inverts
-- the projection's own logic.
--
-- The precedent that settles it is the structured-workout trio
-- (plan_workout_id / workout_step_results / workout_adherence, joined by
-- watch_workout in 20270430_001): which workout a run executed is owner-only.
-- A guided run is a workout the run executed.
--
-- Nothing reads the key on any surface yet, so no consumer regresses. A
-- projection can always be widened once a reader exists and the runner can
-- see what they would be publishing; it cannot un-publish what anonymous
-- readers have already fetched.
--
-- Same column list as 20270430_001; only the metadata denylist grows. CREATE
-- OR REPLACE VIEW is catalog-only — no table scan, no lock beyond the view.

create or replace view public_runs as
select
  r.id,
  r.user_id,
  r.started_at,
  r.duration_s,
  r.distance_m,
  r.elevation_gain_m,
  r.source,
  r.activity_type,
  r.is_dnf,
  r.is_public,
  r.created_at,
  case when is_public_route_by_id(r.route_id) then r.route_id else null end as route_id,
  case when is_public_event_by_id(r.event_id) then r.event_id else null end as event_id,
  r.race_listing_id,
  (r.track_url is not null) as has_track,
  r.fastest_5k_s,
  r.fastest_10k_s,
  r.fastest_half_marathon_s,
  r.fastest_marathon_s,
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
    - 'watch_workout'
    - 'guided_run_id'
    - 'last_modified_at'
    - 'recovered_from_crash'
    - 'in_progress_saved_at'
    - 'in_progress'
    - 'safety_escalated_at'
    - 'expected_return_at'
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
    as metadata,
  r.concluded_at
from runs r
where r.is_public = true;

revoke all on public.public_runs from public, anon, authenticated;
grant select on public_runs to anon, authenticated;
