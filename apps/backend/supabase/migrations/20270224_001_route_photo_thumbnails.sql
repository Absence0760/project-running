-- Server-side thumbnails + EXIF strip for route photos (roadmap backlog
-- row 8, the deferred half of "Photos on runs and routes").
--
-- route_photos already carries `thumb_512_path` (20270114_001) — the
-- column, its owner-prefix shape CHECK, the service-role-only-update
-- trigger, and the storage SELECT policy that accepts the thumb path
-- all landed with the table. That migration explicitly deferred the
-- worker: "No `photo_process` enqueue trigger: the Go worker has no
-- route-photo handler ... thumb_512_path is carried for forward parity
-- but written service-role-only when a worker lands." This is that
-- worker landing.
--
-- What this migration does:
--   1. Widens the jobs.kind CHECK allowlist with `route_photo_process`.
--   2. Adds an AFTER INSERT trigger on route_photos that enqueues one
--      job per uploaded photo, mirroring run_photos' enqueue trigger
--      (20260825_001).
--   3. Adds an AFTER UPDATE OF storage_path trigger to catch the mobile
--      insert-then-PATCH path (placeholder empty path → real path).
--
-- The Go worker's handleRoutePhotoProcess (apps/job_worker) drains the
-- new kind: download → strip JPEG EXIF (defence-in-depth — the web +
-- mobile clients already strip client-side, but a malicious or buggy
-- client could skip it) → generate a 512w thumbnail → upload it
-- alongside the original at `{owner}/{photo_id}_512.jpg` → PATCH the
-- route_photos row's thumb_512_path. Clients then prefer the smaller
-- file in galleries and fall back to the original while the column is
-- still null (worker hasn't caught up with a fresh upload).
--
-- Three-file rule (apps/job_worker/CLAUDE.md "Additional job kinds"):
-- this CHECK widen + the Go dispatch case + the pgtap test extension
-- all land together so the DB rejects the kind at INSERT (23514) until
-- the handler exists, never silently dropping an enqueue.
--
-- Existing data: route photos uploaded before this migration won't be
-- retroactively processed — a one-off backfill if it becomes a concern.
-- New uploads enqueue via the triggers below.
--
-- Race window: identical to run_photos (20260825_001). The worker
-- re-uploads the stripped original to the same path; between upload-
-- complete and strip-complete a non-owner viewing a public/club route
-- could fetch the still-EXIF-bearing original. Window is seconds, and
-- the route must be visible to that non-owner at all. The client-side
-- strip already covers the common path; this worker is defence in depth.

-- ─────────────────── widen jobs.kind allowlist ───────────────────
-- Full re-statement at the chain end (the pattern docs in 20261211_001).

alter table public.jobs drop constraint jobs_kind_chk;
alter table public.jobs
  add constraint jobs_kind_chk
  check (
    kind in (
      'map_match', 'token_refresh', 'strava_event', 'photo_process',
      'notification_email', 'lifecycle_email', 'safety_email', 'web_push',
      'weekly_digest', 'native_push', 'lifecycle_drip', 'route_photo_process'
    )
  );

-- ─────────────────── enqueue trigger on route_photos ───────────────────
-- The web path uploads the object first, then inserts the row with the
-- final storage_path — so AFTER INSERT enqueues directly. The mobile path
-- inserts a placeholder row (empty storage_path), uploads, then PATCHes
-- the real path — so the placeholder insert is skipped here and caught by
-- the AFTER UPDATE trigger below when the path fills in.

create or replace function enqueue_route_photo_process_job()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.storage_path is null or NEW.storage_path = '' then
    return NEW;
  end if;

  insert into public.jobs (kind, payload)
  values (
    'route_photo_process',
    jsonb_build_object(
      'photo_id', NEW.id::text,
      'storage_path', NEW.storage_path,
      'owner_id', NEW.owner_id::text
    )
  );
  return NEW;
end;
$$;

revoke execute on function enqueue_route_photo_process_job() from public;

create trigger route_photos_enqueue_process
  after insert on public.route_photos
  for each row execute function enqueue_route_photo_process_job();

-- ─────────────────── enqueue on placeholder → real-path UPDATE ───────────────────
-- Fires only when storage_path transitions from empty to a real value —
-- never on a caption edit or the service-role thumb PATCH.

create or replace function enqueue_route_photo_process_job_on_path_fill()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (old.storage_path is null or old.storage_path = '')
    and new.storage_path is not null
    and new.storage_path <> ''
  then
    insert into public.jobs (kind, payload)
    values (
      'route_photo_process',
      jsonb_build_object(
        'photo_id', NEW.id::text,
        'storage_path', NEW.storage_path,
        'owner_id', NEW.owner_id::text
      )
    );
  end if;
  return NEW;
end;
$$;

revoke execute on function enqueue_route_photo_process_job_on_path_fill() from public;

create trigger route_photos_enqueue_process_on_path_fill
  after update of storage_path on public.route_photos
  for each row execute function enqueue_route_photo_process_job_on_path_fill();
