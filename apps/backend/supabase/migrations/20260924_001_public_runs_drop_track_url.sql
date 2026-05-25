-- audit/storage + audit/public-rows (2026-05-25) Medium:
-- `public_runs.track_url` leaks the Storage path to anon callers.
--
-- The Storage object itself is no longer directly fetchable by an
-- anon caller (the bucket-level SELECT-to-anon policy was dropped
-- in 20260619_001), so a leaked path is *currently* useless to an
-- attacker. The concern flagged by the audit is defence-in-depth:
-- exposing `{user_id}/{run_id}.json.gz` in the public-readable view
-- means any future loosening of the Storage RLS owner-folder
-- policy immediately re-opens direct download without any code
-- change on the attacker side. The clip-public-track Edge Function
-- derives the path from `user_id + run_id` directly (index.ts:113)
-- and does NOT need the column on the view.
--
-- DROP + CREATE because Postgres rejects column removal via
-- `create or replace view` (42P16).

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
