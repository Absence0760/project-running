-- Treadmill / indoor HR-zone support: per-point heart rate for trackless runs.
--
-- A FIT/TCX record from an indoor or treadmill run carries heart rate +
-- cadence but no GPS fix, so `garmin-fit.ts` emits NO TrackPoint for it and the
-- run imports with `track: []`. `avg_bpm` survives (the stat grid shows average
-- HR), but the per-point `bpm` the run-detail HR-zone breakdown needs is lost,
-- so the zone chart renders blank for exactly the audience that trains by HR.
--
-- Rather than synthesise position-less TrackPoints (which would ripple into
-- every COORDINATE consumer — GPX export emits lat=0/undefined, Waypoint.fromJson
-- throws on a null lat — for zero benefit to the zone chart, which reads only
-- bpm+ts), the HR series lives in its own sidecar Storage object alongside the
-- track: `{user_id}/{run_id}.hr.json.gz`, a gzipped JSON array of
-- `{ bpm: number, ts?: string }`. The `runs` bucket RLS (20260410_001) already
-- gates every `{user_id}/...` path on `auth.uid()`, so the sidecar needs no new
-- bucket and no new Storage policy. This column stores the path; it carries no
-- location data, so it is owner-only audit data and is NEVER exposed through
-- public_runs / clip_track_for_user (see decisions §116).

alter table runs add column hr_series_url text;

-- Mirror the runs_track_url_path_shape CHECK (20260621_001): pin the path to
-- the canonical {user_id}/{run_id}.hr.json.gz so a malicious owner can't
-- rewrite the column to point at another user's blob. NOT VALID then VALIDATE,
-- matching the track_url pattern (the column is brand-new so validation is a
-- formality, but keeping the two columns' enforcement identical is the point).
alter table runs
  add constraint runs_hr_series_url_path_shape
  check (
    hr_series_url is null
    or hr_series_url = user_id::text || '/' || id::text || '.hr.json.gz'
  ) not valid;

alter table runs validate constraint runs_hr_series_url_path_shape;
