-- enqueue_run_rematch — operator hook to force a fresh map-match.
--
-- The auto-enqueue trigger only fires on INSERT and on track_url
-- change, by design. There are real-world cases where a user (or a
-- support session) wants to retry the matcher against the same track:
--   - The matcher version was bumped server-side and the runner wants
--     the new algorithm applied to an existing run.
--   - A transient worker / OSRM outage produced status='failed' and the
--     user is hitting "try again" once the platform is healthy.
--   - The matched line looks visibly off and the user wants a clean
--     retry rather than living with a stale snap.
--
-- The button on `/runs/[id]` calls this RPC. It is SECURITY DEFINER so
-- the function can write to `run_matched_tracks` and `jobs` (both are
-- writable only to the worker via service-role today), but auth is
-- gated on `auth.uid() = run.user_id` so a signed-in caller can only
-- re-match runs they own. No global-admin pathway — there's no
-- cross-user re-match surface today, and adding one would require a
-- new role check that we don't yet have.
--
-- The function deliberately mirrors the trigger's reset shape (status
-- = 'pending', attempts = 0, error_message = null, …) and re-stamps
-- source_track_url to the run's current track_url so the worker's CAS
-- pre-write check (migration 20260611_001) compares against fresh
-- state. Without that re-stamp, a re-match queued after a failed
-- attempt would race the previous job's PATCH on a stale source_url.
--
-- Idempotent against the partial unique index `jobs_dedupe_map_match`
-- — calling twice in quick succession is a no-op on the second call
-- (the first job is still queued or running). Once the previous job
-- finishes and a new re-match is requested, the partial index permits
-- a fresh row.

create or replace function enqueue_run_rematch(p_run_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run_user_id uuid;
  v_track_url text;
begin
  -- Caller must be authenticated AND own the run. Anonymous calls
  -- (auth.uid() is null) fail the second predicate; foreign-user
  -- calls fail it too. The lookup uses the index on runs.id.
  select user_id, track_url
    into v_run_user_id, v_track_url
  from runs
  where id = p_run_id;

  if v_run_user_id is null then
    raise exception 'enqueue_run_rematch: run not found' using errcode = 'P0002';
  end if;

  if auth.uid() is null or auth.uid() <> v_run_user_id then
    raise exception 'enqueue_run_rematch: not authorized' using errcode = '42501';
  end if;

  if v_track_url is null or v_track_url = '' then
    -- A re-match has nothing to chew on without a track. Surface
    -- this as a typed error so the UI can render a clear message
    -- instead of an opaque 500.
    raise exception 'enqueue_run_rematch: run has no track' using errcode = '22000';
  end if;

  -- Reset run_matched_tracks to pending. Mirrors the trigger's UPDATE
  -- branch shape (CAS migration 20260611_001) — same columns cleared,
  -- same source_track_url stamp.
  insert into run_matched_tracks (run_id, status, source_track_url)
  values (p_run_id, 'pending', v_track_url)
  on conflict (run_id) do update
  set status = 'pending',
      source_track_url = v_track_url,
      matched_track_url = null,
      attempts = 0,
      matched_at = null,
      error_message = null,
      algorithm = null,
      algorithm_version = null;

  -- Queue the worker. Idempotent against jobs_dedupe_map_match — a
  -- second call while a previous job is still queued or running is a
  -- no-op, which is what the user wants when they click twice.
  insert into jobs (kind, payload)
  values (
    'map_match',
    jsonb_build_object('run_id', p_run_id, 'user_id', v_run_user_id)
  )
  on conflict do nothing;

  return jsonb_build_object('ok', true);
end;
$$;

-- Authed users only. The function self-checks ownership; granting to
-- 'authenticated' is what lets the EF / web client invoke it via
-- PostgREST without a service-role key.
grant execute on function enqueue_run_rematch(uuid) to authenticated;
revoke execute on function enqueue_run_rematch(uuid) from anon;
