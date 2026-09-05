-- The nightly SQL sweep comes off the clock, and the reaper's enqueue picks up
-- the legacy prefix the sweep was the only thing covering.
--
-- [decisions § 1144] scheduled `enqueue-export-blob-reap` at 04:13, ten minutes
-- ahead of `cleanup-stale-export-blobs` at 04:23, so in the normal case the
-- Storage-API erasure happens before the row delete and the sweep finds nothing
-- left to orphan. That lead is best-effort and it is the wrong shape. A night
-- the worker is down, or a job that fails its three attempts, and the sweep
-- still deletes the `storage.objects` rows at 04:23 — after which the bytes are
-- unreachable by ANY Storage-API reaper, because list reads the rows that are
-- gone ([§ 1049]). The sweep's row delete is now the only thing in the system
-- that can create a permanent orphan, and a clock is exactly the trigger that
-- cannot be conditioned on the erasure having happened.
--
-- What the sweep was buying, measured rather than assumed:
--
--   * ERASURE: none. § 1049 measured the bytes surviving with a matching
--     sha256; a row delete is not an object delete, which is why storage-api
--     ships a trigger refusing one.
--   * REACHABILITY: none either, and this is the half [§ 1049] left implicit.
--     The `exports` bucket carries NO storage.objects policies at all
--     (20270602_001, deliberately), and 20260816_001 carved `exports/` out of
--     the owner-folder SELECT on `runs`. An export is reachable through the
--     10-minute signed URL the server mints and nothing else. So deleting the
--     row removes a reachability nobody had.
--   * EXPIRY of the `data_export_jobs` rows that point at an archive: this one
--     is real, and it is unconditional WITHOUT the sweep. § 1144 moved
--     `expire_stale_export_jobs()` into `enqueue_export_blob_reap()`, which is
--     the pg_cron half and runs whether or not a worker ever claims the job.
--
-- So the sweep is redundant when the reaper works and harmful when it does not.
-- Unscheduling it leaves the failure mode as a bounded retention overrun —
-- rows and bytes both survive, both still erasable, no subject able to reach
-- either — instead of permanent residue. The function itself is kept: it has a
-- `service_role` grant for an operator who wants the unconditional removal of
-- reachability as a break-glass, and `export_surface_contract_test.sql` drives
-- it directly rather than through the schedule.

do $$
begin
  if exists (select 1 from cron.job where jobname = 'cleanup-stale-export-blobs') then
    perform cron.unschedule('cleanup-stale-export-blobs');
  end if;
end $$;

comment on function cleanup_stale_export_blobs() is
  'Break-glass sweep of Art 20 export artifacts older than 7 days, across '
  'both the `exports` bucket (20270602_001) and the legacy '
  '`runs/{user_id}/exports/*` prefix, then expire_stale_export_jobs() for the '
  'data_export_jobs rows that pointed at them (20270603_001). NO LONGER '
  'SCHEDULED (20270709000001): it deletes storage.objects ROWS, which erases '
  'nothing and — once the row is gone — puts the bytes beyond the reach of the '
  'Storage-API reaper that does (export_blob_reap, decisions 1112/1144/1172). '
  'The nightly path is enqueue_export_blob_reap() alone, which also carries '
  'the expire_stale_export_jobs() call unconditionally. Sets '
  'storage.allow_delete_query transaction-locally so storage-api''s '
  'protect_delete() trigger admits the DELETE, and raises if any stale object '
  'survives it. SECURITY DEFINER + executes as the postgres role, which has '
  'bypassrls on Supabase Cloud. service_role grant lets ops invoke it by hand.';

-- ─────────────────── the legacy prefix ───────────────────

-- The sweep reached `runs/{uid}/exports/*` and the reaper's default payload
-- does not: the handler's walk is prefix-scoped and a whole-`runs` walk is
-- O(users) list calls, which is the open question § 1144 left for whoever took
-- this. Answered here: the enqueue derives the prefixes from the rows that
-- actually exist, so it emits one job per user who still HAS a legacy archive
-- and nothing at all once they are erased. Nothing has written that prefix
-- since 20270602_001, so the set is finite and shrinking.
--
-- The singleton guard becomes per-PAYLOAD rather than per-kind. Two queued
-- reaps of the same worklist are still not two sweeps — the second re-lists and
-- finds the first's work done — but the default `exports` job and a
-- prefix-scoped `runs` job are different worklists, and a kind-wide guard would
-- let whichever was inserted first suppress the others every night.
create or replace function enqueue_export_blob_reap()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform expire_stale_export_jobs();

  insert into public.jobs (kind, payload, max_attempts)
  select 'export_blob_reap', p.payload, 3
  from (
    select '{}'::jsonb as payload
    union all
    select jsonb_build_object('bucket', 'runs', 'prefix', o.uid || '/exports/')
    from (
      select distinct split_part(name, '/', 1) as uid
      from storage.objects
      where bucket_id = 'runs'
        and name like '%/exports/%'
    ) o
  ) p
  where not exists (
    select 1 from public.jobs j
    where j.kind = 'export_blob_reap'
      and j.status in ('queued', 'running')
      and j.payload = p.payload
  );
end;
$$;

comment on function public.enqueue_export_blob_reap() is
  'Queues the nightly Art 20 export-archive reap for the Go worker '
  '(kind export_blob_reap, decisions 1112) and expires the data_export_jobs '
  'rows that pointed at the archives it is about to erase. One job for the '
  '`exports` bucket plus one per user who still has a legacy '
  '`runs/{uid}/exports/*` archive, the set derived from storage.objects so it '
  'empties itself; singleton per PAYLOAD, so a night the worker was down '
  'cannot stack identical sweeps. Since 20270709000001 this is the ONLY '
  'scheduled half of export retention — cleanup_stale_export_blobs is '
  'unscheduled break-glass, because its row delete orphans the bytes it '
  'cannot erase (decisions 1172). service_role grant lets an operator invoke '
  'this by hand.';
