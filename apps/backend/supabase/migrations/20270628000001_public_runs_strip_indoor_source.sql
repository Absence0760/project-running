-- Strip metadata.indoor_source from public_runs, joining the synonym that
-- was already stripped.
--
-- Four keys describe an indoor run and they were split across the projection
-- incoherently: `indoor` and `indoor_source` public, `indoor_estimated` and
-- `distance_source` stripped. The middle two are the sharp case —
-- `distance_source: "treadmill"` and `indoor_source: "treadmill"` carry the
-- same fact in the same words, are written on the same run by the same
-- recorder path, and landed on opposite sides of the view.
--
-- The line that makes them coherent is fact versus provenance. THAT a run
-- was indoors is a property of the run, useful on a share page and carrying
-- no signal about the runner beyond where the feet landed — the `sub_sport`
-- class, and `indoor` stays public for that reason. WHICH SENSOR produced the
-- distance is a recorder internal; `docs/backend/metadata.md` marks both
-- `indoor_source` and `distance_source` audit-only, and neither has a reader
-- on any surface. `indoor_estimated` and `distance_source` were already on
-- the owner-only side; `indoor_source` was public only by omission, never by
-- a decision anyone recorded.
--
-- The registry has carried this as a known leak since it was written,
-- classified public-safe "to match reality" rather than on its merits, with
-- an invitation to strip it in the next projection migration. This is that
-- migration. Nothing reads the key, so no consumer regresses.
--
-- Same column list as 20270627000001; only the metadata denylist grows.
-- CREATE OR REPLACE VIEW is catalog-only — no table scan, no lock beyond the
-- view.

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
    - 'indoor_source'
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
