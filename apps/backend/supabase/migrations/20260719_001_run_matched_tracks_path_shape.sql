-- Lock `run_matched_tracks.matched_track_url` to the canonical
-- `{user_id}/{run_id}.matched.json.gz` shape.
--
-- Audit pass 2 finding: `runs.track_url` was locked by `20260621_001`,
-- but the sibling column `run_matched_tracks.matched_track_url` —
-- written by the Go map-match worker — has no constraint. The web
-- client downloads via `fetchRunMatchedTrack → fetchTrack` against
-- the user-scoped Supabase client, so the Storage RLS owner-folder
-- check (`(storage.foldername(name))[1] = auth.uid()::text`) is the
-- gate against cross-user reads. That's the same posture as before
-- `20260621_001` for the runs bucket. The CHECK constraint is
-- defence-in-depth: it pins write-time correctness so a future bug
-- in the Go worker (or a future ALTER policy that opens UPDATE on
-- this column to authenticated users) cannot land a malformed path
-- without the DB rejecting it.
--
-- The path shape carries the row's own `run_id` so we can validate
-- structurally — the user_id is at the prefix (the worker writes
-- `<user_id>/<run_id>.matched.json.gz` per `apps/job_worker/internal/worker/worker.go`).
-- The regex pins both halves:
--   - first segment: 36-char UUID hex+dash
--   - separator: literal '/'
--   - second segment: this row's run_id (UUID-format checked by the
--     PK column type) + literal `.matched.json.gz`

alter table run_matched_tracks
  add constraint run_matched_tracks_matched_track_url_shape
  check (
    matched_track_url is null
    or matched_track_url ~ ('^[0-9a-f-]{36}/' || run_id::text || '\.matched\.json\.gz$')
  );

alter table run_matched_tracks
  validate constraint run_matched_tracks_matched_track_url_shape;
