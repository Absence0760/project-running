-- Surface permanently-failed `jobs` rows so an operator notices when a
-- background job dies, and close the one failure class that was
-- previously invisible to every alert.
--
-- Why this matters now: the Strava webhook moved off the synchronous
-- Edge Function (`strava-webhook`) onto the Go worker's async
-- `kind='strava_event'` pipeline. The EF used to ack Strava with a
-- non-200 when ingest failed, so Strava retried and a human eventually
-- saw the failure. The Go path acks 200 immediately and enqueues a
-- job; if that job then fails (a bad payload, a Storage write error, a
-- 4xx from the run insert), the failure now lives only in the `jobs`
-- table. Nothing watches it.
--
-- There were TWO silent-failure classes:
--
--   1. Permanent failure — the worker calls `finish_job(failed, msg)`,
--      so the row lands in `status='failed'` with `last_error` set.
--      Visible if you query for it, but no alert fired. This migration
--      adds the alert.
--
--   2. Exhausted transient — the worker calls `defer_job` on a
--      transient error, which re-queued the row. But `claim_next_job`
--      gates on `attempts < max_attempts`, so once the ceiling is hit
--      the row sat in `status='queued'` FOREVER, un-claimable, never
--      transitioning to `failed`, invisible to `find_stuck_jobs`
--      (running-only) and to a queue-lag alert (it can't tell an
--      exhausted job from a fresh one). This migration changes
--      `defer_job` to land an exhausted retry in `status='failed'`
--      instead, routing it into the same surface as class 1.
--
-- Race note: unlike `find_stuck_jobs` (which deliberately does NOT
-- auto-fail rows, because an external observer could race a worker
-- about to call `finish_job` on the same row), flipping to `failed`
-- inside `defer_job` is race-free — it is the worker that holds the
-- job calling its own terminal action for the attempt it just ran. No
-- other worker can touch the row (it was claimed `for update skip
-- locked` with `locked_by` = this worker), so this is the same code
-- path that would otherwise re-queue, just choosing a terminal state.

-- ─── defer_job: exhausted retries become `failed`, not `queued` ───
-- Complete body re-emitted from 20260609_001 (the only prior
-- definition) with the exhaustion branch added. `attempts` is bumped
-- on claim, so by the time the worker calls defer_job the value
-- already reflects the attempt that just failed.
create or replace function defer_job(
  job_id bigint,
  delay_seconds integer,
  err text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_attempts smallint;
  v_max      smallint;
begin
  if delay_seconds < 0 then
    raise exception 'defer_job: delay_seconds must be >= 0'
      using errcode = '22023';
  end if;

  select attempts, max_attempts
    into v_attempts, v_max
  from jobs
  where id = job_id;

  if v_attempts is null then
    return;  -- row vanished (purged / cancelled mid-flight); nothing to do
  end if;

  if v_attempts >= v_max then
    -- Retry budget spent. Re-queuing would strand the row in 'queued'
    -- forever (claim_next_job requires attempts < max_attempts), so
    -- land it terminally in 'failed' where jobs_failed_summary sees it.
    update jobs
    set status = 'failed',
        finished_at = now(),
        locked_at = null,
        locked_by = null,
        last_error = err
    where id = job_id;
  else
    update jobs
    set status = 'queued',
        scheduled_at = now() + (delay_seconds || ' seconds')::interval,
        locked_at = null,
        locked_by = null,
        last_error = err
    where id = job_id;
  end if;
end;
$$;

revoke execute on function defer_job(bigint, integer, text) from public;
grant execute on function defer_job(bigint, integer, text) to service_role;

-- ─── find_failed_jobs: recently-terminated rows ─────────────────
-- Mirror of find_stuck_jobs. Windowed on finished_at because failed
-- rows are NOT purged (the data-retention cron only sweeps user-data
-- tables), so an unbounded query would alert forever on old failures.
-- The window is the alert's "what failed since I last looked" lens.
create or replace function find_failed_jobs(
  p_failed_within interval default interval '15 minutes'
)
returns table (
  id          bigint,
  kind        text,
  attempts    smallint,
  finished_at timestamptz,
  last_error  text,
  age         interval
)
language sql
stable
security definer
set search_path = public
as $$
  select
    j.id,
    j.kind,
    j.attempts,
    j.finished_at,
    j.last_error,
    now() - j.finished_at as age
  from jobs j
  where j.status = 'failed'
    and j.finished_at is not null
    and (now() - j.finished_at) <= p_failed_within
  order by j.finished_at desc;
$$;

revoke execute on function find_failed_jobs(interval) from public;
grant execute on function find_failed_jobs(interval) to service_role;

-- ─── jobs_failed_summary: count + sample for the cron run-details ──
-- Single-row JSON so the value is readable in
-- cron.job_run_details.return_message. Real alerting (PagerDuty /
-- Slack) routes on failed_count > 0; the per-kind breakdown helps an
-- operator see at a glance whether one handler is the culprit.
create or replace function jobs_failed_summary(
  p_failed_within interval default interval '15 minutes'
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'failed_count', count(*),
    'by_kind',      coalesce(
      (select jsonb_object_agg(k.kind, k.n)
       from (
         select kind, count(*) as n
         from find_failed_jobs(p_failed_within)
         group by kind
       ) k),
      '{}'::jsonb
    ),
    'sample',       coalesce(
      (select jsonb_agg(
         jsonb_build_object(
           'id',         s.id,
           'kind',       s.kind,
           'attempts',   s.attempts,
           'age_s',      extract(epoch from s.age)::int,
           'last_error', left(s.last_error, 200)
         ) order by s.age asc
       )
       from (
         select * from find_failed_jobs(p_failed_within) limit 5
       ) s),
      '[]'::jsonb
    ),
    'checked_at', now()
  )
  from find_failed_jobs(p_failed_within);
$$;

revoke execute on function jobs_failed_summary(interval) from public;
grant execute on function jobs_failed_summary(interval) to service_role;

-- Schedule every 10 min, matching the stuck-job alert cadence. The
-- 15-min default window overlaps the 10-min cadence so a failure
-- between two fires is never missed. Idempotent — same-name schedule
-- is a no-op on re-run.
select cron.schedule(
  'jobs-failed-alert',
  '*/10 * * * *',
  $$select public.jobs_failed_summary()$$
);

comment on function find_failed_jobs(interval) is
  'Lists jobs that terminated in status=''failed'' within the given '
  'window (default 15 min). Includes the worker''s permanent-failure '
  'finish_job(failed) rows and the exhausted-transient rows that '
  'defer_job now fails instead of re-queuing. Read-only.';

comment on function jobs_failed_summary(interval) is
  'Count + per-kind breakdown + sample of recently-failed jobs, as a '
  'single JSONB row for cron.job_run_details. Scheduled by pg_cron '
  'entry `jobs-failed-alert` (every 10 min). A future Sentry / Slack '
  'scraper routes on failed_count > 0.';
