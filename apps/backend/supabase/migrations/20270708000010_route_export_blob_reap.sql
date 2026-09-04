-- Route `export_blob_reap`: the CHECK that lets it be enqueued, the enqueue
-- itself, and the schedule that fires it.
--
-- [decisions § 1049] measured that `cleanup_stale_export_blobs()` deletes rows
-- from `storage.objects` and leaves the bytes on the backend with a matching
-- sha256 — a row delete is not an object delete, which is why storage-api
-- ships a trigger refusing one. The sweep buys reachability, not erasure, and
-- the SQL tier cannot buy more than that. [§ 1112] landed the Go handler that
-- erases through the Storage API, and shipped it deliberately unroutable:
-- `apps/job_worker/internal/worker_dispatch_coverage_test.go` fails a
-- `case` for a kind this CHECK forbids, and fails the absence of one for a
-- kind it admits. So this migration and the dispatch line are one change —
-- either alone is red, in opposite directions.

-- ─────────────────── 1. jobs_kind_chk ───────────────────

-- The online two-step, for the reason 20270603_001 spells out: `jobs` is a
-- queue that accumulates finished rows, and a validating ADD holds ACCESS
-- EXCLUSIVE while it scans all of them. Every existing row already satisfies
-- the wider set — this only ever ADDS a kind — so the scan is pure waste, and
-- VALIDATE runs it under SHARE UPDATE EXCLUSIVE with reads and writes
-- proceeding. Both halves are here rather than split across migrations
-- because the scan is of the queue, not of `runs`; the lock class is what
-- mattered (migration_locks.md § CHECK constraints).
alter table public.jobs
  drop constraint jobs_kind_chk;
alter table public.jobs
  add constraint jobs_kind_chk
  check (
    kind in (
      'map_match', 'token_refresh', 'strava_event', 'photo_process',
      'notification_email', 'lifecycle_email', 'safety_email', 'web_push',
      'weekly_digest', 'native_push', 'lifecycle_drip', 'route_photo_process',
      'club_photo_process', 'safety_sms', 'data_export', 'export_blob_reap'
    )
  )
  not valid;
alter table public.jobs
  validate constraint jobs_kind_chk;

-- ─────────────────── 2. enqueue_export_blob_reap ───────────────────

-- A singleton. Two queued reaps are not two sweeps: the second re-lists and
-- finds the first's work already done, so a week of nights during which the
-- worker was down would leave seven identical jobs to drain and no extra
-- erasure. The `where not exists` is against the daily schedule and an
-- operator's manual call, which cannot race each other; a partial unique
-- index would need `create unique index concurrently`, which errors inside
-- the wrapped apply transaction (migration_locks.md § Lock reference).
--
-- The empty payload is the whole contract: the handler reads it as the
-- `exports` bucket at its default window, which is this sweep's own seven
-- days and is pinned by a Go test against drift.
--
-- max_attempts 3 rather than the table's 5. A reap is idempotent and cheap to
-- retry — it re-lists, so a second attempt cannot re-erase — but a transport
-- fault that survives three attempts is an outage, not a blip, and the next
-- night's job re-derives the same worklist anyway.
--
-- `expire_stale_export_jobs()` runs HERE, not only in the sweep ten minutes
-- later, and the order is the point. It is what removes reachability: it
-- flips a `ready` row to `expired` and nulls its `object_path`. Without it a
-- subject asking for their latest export in the window between the reap and
-- the sweep is handed a path to an archive the reaper has just erased — a 404
-- where "expired" is the true answer. Reachability first, erasure second, is
-- the ordering § 1049 argued for; it is idempotent and the sweep still calls
-- it, so nothing is lost if this half is skipped.
create or replace function enqueue_export_blob_reap()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform expire_stale_export_jobs();

  insert into public.jobs (kind, payload, max_attempts)
  select 'export_blob_reap', '{}'::jsonb, 3
  where not exists (
    select 1 from public.jobs j
    where j.kind = 'export_blob_reap'
      and j.status in ('queued', 'running')
  );
end;
$$;

revoke execute on function public.enqueue_export_blob_reap() from public, anon, authenticated;
grant execute on function public.enqueue_export_blob_reap() to service_role;

comment on function public.enqueue_export_blob_reap() is
  'Queues the nightly Art 20 export-archive reap for the Go worker '
  '(kind export_blob_reap, decisions 1112) and expires the '
  'data_export_jobs rows that pointed at the archives it is about to '
  'erase. Singleton: a night the worker was down cannot stack '
  'identical sweeps. Scheduled by pg_cron ten minutes ahead of '
  'cleanup-stale-export-blobs; service_role grant lets an operator '
  'invoke it by hand.';

-- ─────────────────── 3. schedule ───────────────────

-- Ten minutes ahead of `cleanup-stale-export-blobs`'s '23 4 * * *'. The
-- worker polls every 2s, so the reap has finished long before the sweep runs
-- and the sweep then finds no rows to delete for objects nothing erased —
-- which is exactly the orphaned-byte state § 1049 measured. The lead is
-- best-effort, not a guarantee: a worker that is down at 04:13 leaves the
-- sweep to delete the rows at 04:23, and the bytes join the pile the § 1049
-- residue entry tracks. Keeping the sweep is deliberate — removing
-- reachability is the part SQL can do unconditionally, and it is the right
-- fail-safe when the erasure tier is unavailable.
--
-- pg_cron's extension is created by 20260602_001; `cron.schedule` is
-- idempotent on name, so re-applying this migration silently no-ops.
select cron.schedule(
  'enqueue-export-blob-reap',
  '13 4 * * *',
  $$select public.enqueue_export_blob_reap()$$
);
