-- Extend the `jobs.kind` CHECK allowlist to admit `photo_process`,
-- the kind enqueued by an AFTER INSERT trigger on `run_photos` and
-- drained by the Go worker's `handler_photo_process.go`. The handler
-- downloads the photo bytes from the `run-photos` Storage bucket,
-- strips JPEG APP1 (EXIF) markers — which carry GPS coordinates,
-- camera model, capture timestamp, and other identifying metadata —
-- and re-uploads in place. Mirrors what Strava, AllTrails, and
-- competitor apps do server-side to prevent uploaded photos from
-- leaking location data via EXIF.
--
-- Three-file rule (per `apps/job_worker/CLAUDE.md` "Build here →
-- Additional job kinds"): a new kind requires the migration +
-- the Go dispatch case + the pgtap test (extended in this same
-- commit at `apps/backend/supabase/tests/jobs_kind_allowlist_test.sql`).
-- Until all three land, the CHECK rejects inserts at 23514 so the
-- trigger can't silently drop events.
--
-- Existing data: no `photo_process` rows exist before this commit.
-- Photos already uploaded before this migration won't be retroactively
-- stripped — that's a one-off backfill if it becomes a real concern.
-- New photos uploaded after this migration enqueue a job via the
-- AFTER INSERT trigger below.
--
-- Race window: the worker re-uploads to the same Storage path as the
-- original photo. Between the client's upload-complete and the
-- worker's strip-complete, a non-owner viewer could fetch the
-- still-EXIF-bearing original. The window is typically a few
-- seconds; the photo's run also has to be public for non-owners to
-- read it at all (per `20260705_001_run_photos_storage_visibility_gate`).
-- A staging-path scheme would close this fully but adds complexity;
-- revisit if the race ever fires in anger.

alter table public.jobs
  drop constraint jobs_kind_chk;

alter table public.jobs
  add constraint jobs_kind_chk
  check (kind in ('map_match', 'token_refresh', 'strava_event', 'photo_process'));

-- ─────────────────── enqueue trigger on run_photos ───────────────────

create or replace function enqueue_photo_process_job()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.jobs (kind, payload)
  values (
    'photo_process',
    jsonb_build_object(
      'photo_id', NEW.id::text,
      'storage_path', NEW.storage_path,
      'owner_id', NEW.owner_id::text
    )
  );
  return NEW;
end;
$$;

revoke execute on function enqueue_photo_process_job() from public;
-- The trigger is fired by the row insert, not invoked directly —
-- the function only needs to be callable from the trigger context,
-- which security definer handles. No grant to public, anon, or
-- authenticated needed.

create trigger run_photos_enqueue_process
  after insert on public.run_photos
  for each row execute function enqueue_photo_process_job();
