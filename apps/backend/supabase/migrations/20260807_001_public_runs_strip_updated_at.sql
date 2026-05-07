-- /audit/all Medium: `public_runs.updated_at` leaks the runner's
-- last-edit / last-sync timestamp on every public run. The same view
-- already strips `metadata.last_modified_at` ("leaks device-upload
-- cadence") — `runs.updated_at` carries the same signal at the
-- column level. An observer with a share link can poll
-- `?id=eq.<x>&select=updated_at` to infer when the runner last
-- synced or edited the run.
--
-- Verified across the repo: no render path on web or mobile reads
-- `updated_at` from a public_runs row. Owner-side reads of
-- `runs.updated_at` go through the base `runs` table, not this view.
-- Stripping is therefore a pure wire-format tightening with no UI
-- dependency.
--
-- The companion finding on `public_runs.source` (platform provider
-- provenance — strava / garmin / healthkit) is intentionally
-- preserved: `RunShareView.svelte:85` renders it as a source badge.
-- That trade-off (recognisable provider context outweighs the
-- minor reconnaissance value) is now explicitly documented in
-- `docs/api_database.md` rather than left as a silent omission.

-- DROP + CREATE rather than REPLACE: Postgres rejects column removal
-- via `create or replace view` (42P16 — "cannot drop columns from view").
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
  r.track_url,
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
