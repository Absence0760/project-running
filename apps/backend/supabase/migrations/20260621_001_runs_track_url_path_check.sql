-- Pin runs.track_url to the canonical {user_id}/{run_id}.json.gz
-- shape so a malicious owner can't rewrite the column to point at
-- another user's blob.
--
-- audit/storage re-audit High finding. The clip-public-track Edge
-- Function (apps/backend/supabase/functions/clip-public-track/
-- index.ts) reads runs.track_url from the caller-RLS-gated row
-- and downloads that path verbatim via service-role to bypass the
-- per-user-folder Storage policy. There was no constraint forcing
-- track_url to match {user_id}/{run_id}.json.gz, and the
-- runs UPDATE policy is `auth.uid() = user_id`, so a user could
-- rewrite their own row's track_url to any victim's path:
--
--   update runs set track_url = '<victim_user>/<victim_run>.json.gz'
--     where id = '<my_run_id>';
--
-- Then any caller (including anon via /share/run/[id]) hitting the
-- EF for that run would get the victim's full unclipped track —
-- the EF clips against the row's user_id (the attacker), and an
-- attacker with no privacy zones makes the clip a no-op.
--
-- Two enforcement layers:
--   1. CHECK constraint here. Load-bearing — kills the forge at
--      write time.
--   2. EF assertion (separate change). Defence-in-depth — catches
--      the rare row that landed before this migration applied,
--      and keeps the EF safe even if the CHECK is ever weakened.
--
-- Every legitimate writer (web `data.ts:593`, mobile
-- `api_client.dart:435`, Strava `_shared/strava.ts:203`, parkrun
-- importer) already uses `${user_id}/${run_id}.json.gz`. The
-- pre-existing rows in seed.sql + any user data follow the same
-- shape. The CHECK is `NOT VALID` initially so the migration
-- doesn't fail on legacy rows that may have drifted; we then
-- VALIDATE to pull them in. If validation fails on a real
-- deployment, the offender is investigated separately — failing
-- closed (NOT VALID-only) would let the forge keep working on the
-- exact rows we care about most.

alter table runs
  add constraint runs_track_url_path_shape
  check (
    track_url is null
    or track_url = user_id::text || '/' || id::text || '.json.gz'
  ) not valid;

alter table runs validate constraint runs_track_url_path_shape;
