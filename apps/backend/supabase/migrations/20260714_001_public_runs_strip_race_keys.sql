-- Strip race-source metadata + perceived_effort from `public_runs`.
--
-- Audit pass 2 found four `metadata` keys present on `source = 'race'`
-- runs (documented in `api_database.md` § runs) that the public_runs
-- view did not strip:
--
--   - `race_name`  — links the runner to a specific race registration
--   - `bib`        — permanent real-world identity link
--   - `overall_place` — public on the race results page already, but
--                       conservatively owner-only here
--   - `chip_time`  — redundant with `duration_s` but reveals chip vs
--                    gun-time precision the runner may not want public
--
-- Audit pass 2 also found `perceived_effort` written into the runs
-- seed (apps/backend/supabase/seed.sql) for public runs but absent
-- from the registry and the strip list. No application code writes
-- it today, but seed runs travel through the view to anon test
-- clients with the value exposed. Same shape — strip, register
-- owner-only.
--
-- Same shape as the 20260626_001 base view; the strip chain is
-- additive, no other column or behaviour changes.

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
    -- Pass-2 additions:
    - 'race_name'
    - 'bib'
    - 'overall_place'
    - 'chip_time'
    - 'perceived_effort'
    as metadata
from runs r
where r.is_public = true;

grant select on public_runs to anon, authenticated;
