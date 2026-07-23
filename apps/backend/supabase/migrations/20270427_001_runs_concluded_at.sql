-- Positive live-finish marker for the spectator page.
--
-- Until now a live-broadcast run had no reliable "the runner stopped" signal:
-- endLiveBroadcast() DELETEd every live_run_pings row, and the spectator page
-- inferred "finished" purely from started_at + duration_s being >2 min in the
-- past. That inference is fragile — a spectator watching at stop-time just sees
-- pings stop arriving and the feed go stale (never a clean conclusion), and a
-- reload in the first ~2 min after stop lands on a blank/connecting page
-- because the pings were already wiped but the staleness threshold hasn't
-- tripped. If the final duration_s never got written, the run looks like it
-- never completed at all.
--
-- concluded_at is the positive terminal marker the recorder stamps when the run
-- actually finishes (concludeLiveBroadcast). It is nullable with no default, so
-- the ADD COLUMN is an instant catalog-only change on the populated runs table
-- (no rewrite, no scan) — the online-safe shape (cf. hr_series_url,
-- 20261127_001). Both spectator surfaces switch from the duration_s inference
-- to reading this column, and the recorder stops wiping the pings on stop (the
-- 48h retention cron, 20270119_001, still bounds them) so a frozen trace + a
-- real conclusion survive the stop instead of a blank feed.

alter table public.runs
  add column concluded_at timestamptz;

comment on column public.runs.concluded_at is
  'When a live-broadcast run was concluded by the recorder (concludeLiveBroadcast). '
  'The positive spectator finish signal — replaces the started_at + duration_s '
  'staleness inference. NULL for runs that were never live-broadcast or are still live.';

-- Expose it on the anon spectator read path. Same column list as 20270410_001;
-- concluded_at is appended at the END because CREATE OR REPLACE VIEW may only
-- add columns to the tail of the select list (it cannot reorder existing ones).
-- concluded_at is not private (it is the finish signal we WANT anon to read), so
-- it stays out of the metadata denylist below.
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
