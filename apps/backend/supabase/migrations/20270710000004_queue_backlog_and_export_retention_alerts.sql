-- A worker that is DOWN is invisible to both existing job alerts, and export
-- retention is the case where that silence has a deadline.
--
-- [decisions § 1172] took `cleanup-stale-export-blobs` off the clock because
-- its `storage.objects` row delete was the only thing in the system that could
-- permanently orphan a byte. That was right, and it left export retention
-- resting entirely on `export_blob_reap` reaching a Go worker. What went with
-- the schedule was the nightly `raise` `20270703000002` added: the sweep's
-- post-condition check only fires when something calls it, and nothing calls
-- it any more.
--
-- ── the gap is wider than exports, measured ────────────────────────────────
-- `find_stuck_jobs` selects `status = 'running' and locked_at is not null`.
-- `find_failed_jobs` selects `status = 'failed'`. A job that no worker ever
-- CLAIMED is `queued` with a null `locked_at`, so it is in neither set. Both
-- alerts therefore report a healthy queue for as long as the worker is down,
-- and they report it every ten minutes.
--
-- That is not an export problem. It is every kind in the allowlist, and two of
-- them are worse than a retention overrun: `safety_sms` / `safety_email` carry
-- the overdue-runner escalation to a trusted contact, and `data_export` is Art
-- 20 fulfilment. `apps/job_worker/deployment.md` says of the failed-jobs alert
-- that it "is the safety net the async webhook needs" — it is, for a worker
-- that runs and fails, which is the case `defer_job` was taught to flip into
-- `failed` so it could not stall un-claimable in `queued`. A worker that is not
-- running at all never reaches `defer_job` either.
--
-- ── 1. the queue-drain alert ───────────────────────────────────────────────
-- The same shape as its two siblings, so the observability scraper reads one
-- pattern: a `find_*` table function and a `*_summary` returning the jsonb that
-- lands in `cron.job_run_details.return_message`.
--
-- `scheduled_at` rather than `created_at` is the clock, so a deliberately
-- deferred job is not a backlogged one — `now() - scheduled_at` is negative for
-- a job whose time has not come, and negative never exceeds a positive
-- interval.
--
-- One hour is the default because the worker polls every two seconds and every
-- kind but the fan-outs is near-instant. It is a parameter, not a constant, for
-- the case that decides the number in practice: `enqueue_weekly_digests` and
-- `enqueue_lifecycle_drip` insert one job per eligible user in a single burst,
-- so a growing user base is what will first make an honest backlog look like a
-- broken one. Raise the argument on the cron entry rather than the default,
-- which is also what an operator debugging a specific kind wants to lower.
create or replace function find_backlogged_jobs(p_queued_after interval default '01:00:00'::interval)
returns table (
  id bigint,
  kind text,
  scheduled_at timestamptz,
  attempts smallint,
  age interval
)
language sql
stable
security definer
set search_path = public
as $$
  select
    j.id,
    j.kind,
    j.scheduled_at,
    j.attempts,
    now() - j.scheduled_at as age
  from jobs j
  where j.status = 'queued'
    and (now() - j.scheduled_at) > p_queued_after
  order by j.scheduled_at asc;
$$;

create or replace function jobs_backlog_summary(p_queued_after interval default '01:00:00'::interval)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'backlogged_count', count(*),
    'oldest_age_s',     coalesce(extract(epoch from max(age))::int, 0),
    'by_kind',          coalesce(
      (select jsonb_object_agg(k.kind, k.n)
       from (
         select kind, count(*) as n
         from find_backlogged_jobs(p_queued_after)
         group by kind
       ) k),
      '{}'::jsonb
    ),
    'sample',           coalesce(
      (select jsonb_agg(
         jsonb_build_object(
           'id',       s.id,
           'kind',     s.kind,
           'attempts', s.attempts,
           'age_s',    extract(epoch from s.age)::int
         ) order by s.age desc
       )
       from (
         select * from find_backlogged_jobs(p_queued_after) limit 5
       ) s),
      '[]'::jsonb
    ),
    'checked_at', now()
  )
  from find_backlogged_jobs(p_queued_after);
$$;

revoke execute on function public.find_backlogged_jobs(interval) from public, anon, authenticated;
revoke execute on function public.jobs_backlog_summary(interval) from public, anon, authenticated;
grant execute on function public.find_backlogged_jobs(interval) to service_role;
grant execute on function public.jobs_backlog_summary(interval) to service_role;

comment on function public.jobs_backlog_summary(interval) is
  'Queued jobs nobody has claimed, for the observability scraper. The third '
  'alert beside jobs_stuck_summary (running-but-wedged) and '
  'jobs_failed_summary (terminally failed), covering the case neither can see: '
  'a worker that is not running at all leaves every job queued with a null '
  'locked_at, which is in neither of their sets. Route the scraper on '
  'backlogged_count > 0.';

-- ── 2. the retention overrun itself ────────────────────────────────────────
-- The backlog alert above catches the cause. This catches the CONDITION, which
-- is not the same claim: a reap job that is claimed, runs, and whose Go handler
-- erases nothing is `done` and drains the backlog while the bytes stay. Only a
-- count over `storage.objects` can tell.
--
-- The window is the sweep's own `7 days` plus a grace day. The grace is not
-- decoration: objects cross the retention line continuously and the reap runs
-- once a night at 04:13, so at any instant up to a day's worth of archives are
-- legitimately past 7 days and waiting for the next run. Alerting on those
-- would fire every day forever, which is the same as not alerting.
--
-- It RETURNS rather than raises, unlike `cleanup_stale_export_blobs`. That
-- raise is a post-condition on a mutation the function just performed — a
-- DELETE that was filtered rather than refused must not read as a night with
-- nothing to sweep. A standing check has no mutation to contradict, and one
-- that raised would put a failed row in `cron.job_run_details` every day for as
-- long as a recoverable overrun lasted, training the operator to ignore the one
-- table a real cron failure shows up in.
--
-- Both prefixes, because both hold archives: the `exports` bucket
-- (20270602_001) and the legacy `runs/{uid}/exports/` prefix nothing has
-- written since. The predicate is the sweep's, verbatim, so the alert and the
-- reaper cannot come to disagree about what an export artifact is.
create or replace function export_retention_overrun(p_grace interval default '1 day'::interval)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'overrun_count',  count(*),
    'oldest_age_s',   coalesce(extract(epoch from max(now() - created_at))::int, 0),
    'by_bucket',      coalesce(jsonb_object_agg(bucket_id, n) filter (where bucket_id is not null), '{}'::jsonb),
    'retention_days', 7,
    'grace_s',        extract(epoch from p_grace)::int,
    'checked_at',     now()
  )
  from (
    select o.bucket_id, o.created_at, count(*) over (partition by o.bucket_id) as n
    from storage.objects o
    where (
        (o.bucket_id = 'runs' and o.name like '%/exports/%')
        or o.bucket_id = 'exports'
      )
      and o.created_at < now() - interval '7 days' - p_grace
  ) stale;
$$;

revoke execute on function public.export_retention_overrun(interval) from public, anon, authenticated;
grant execute on function public.export_retention_overrun(interval) to service_role;

comment on function public.export_retention_overrun(interval) is
  'Art 20 export artifacts still on Storage past the 7-day retention window '
  'plus a grace day, for the observability scraper. The condition half of '
  'export retention: jobs_backlog_summary catches a reap nobody claimed, this '
  'catches a reap that ran and erased nothing. Returns rather than raising -- '
  'a standing check that raised would fail a cron run every day for as long as '
  'a recoverable overrun lasted (decisions 1234). Route the scraper on '
  'overrun_count > 0.';

-- ── 3. the schedules ───────────────────────────────────────────────────────
-- Every ten minutes for the backlog, matching its two siblings: the cost is one
-- indexed scan of `jobs` and the point is to notice a dead worker in minutes
-- rather than at the next daily sweep.
--
-- Daily for the retention overrun, at 04:43 -- thirty minutes after the reap at
-- 04:13, so a night on which the worker DID drain the queue has finished
-- erasing before the count is taken. Nothing enforces that ordering and nothing
-- needs to: the grace day means a lag of half an hour, or of half a day, cannot
-- turn a healthy night into an alert.
select cron.schedule(
  'jobs-backlog-alert',
  '*/10 * * * *',
  $$select public.jobs_backlog_summary()$$
);

select cron.schedule(
  'export-retention-overrun-alert',
  '43 4 * * *',
  $$select public.export_retention_overrun()$$
);
