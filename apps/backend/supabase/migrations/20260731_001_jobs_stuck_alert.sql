-- Surface long-running `jobs` rows so an operator can investigate
-- before they starve higher-priority work.
--
-- Why this matters now: round-9 (`20260730_001`) made map-match
-- priority depend on `scheduled_at` ordering. If a single job ever
-- gets stuck in `status='running'` for an extended period (a wedged
-- OSRM call, a network partition that prevented finish_job from
-- writing back, a worker process killed mid-handle), the worker may
-- spin on retries while Pro jobs queue behind it. The contract is
-- that every `kind` completes in < 30 s; anything older than the
-- alert threshold is by definition broken.
--
-- The function is read-only — it identifies stuck jobs but does NOT
-- touch their status. Auto-failing them would race a worker that's
-- about to call `finish_job` for the same row and corrupt the
-- result. Operator-driven remediation only: investigate, then
-- `update jobs set status='failed' where id = ...` if confirmed.
--
-- Output: each stuck row's id, kind, locked_by, locked_at, attempts,
-- and age. Returned as a result set so:
--   1. The pg_cron schedule's run-details captures the row count + a
--      sample, visible in `cron.job_run_details` (Supabase Cloud
--      surfaces this in the dashboard).
--   2. An operator querying the function directly gets the live list.
--   3. A future Sentry / Grafana scraper can `select count(*)` on it.

create or replace function find_stuck_jobs(
  p_stuck_after interval default interval '5 minutes'
)
returns table (
  id          bigint,
  kind        text,
  locked_by   text,
  locked_at   timestamptz,
  attempts    smallint,
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
    j.locked_by,
    j.locked_at,
    j.attempts,
    now() - j.locked_at as age
  from jobs j
  where j.status = 'running'
    and j.locked_at is not null
    and (now() - j.locked_at) > p_stuck_after
  order by j.locked_at asc;
$$;

revoke execute on function find_stuck_jobs(interval) from public;
grant execute on function find_stuck_jobs(interval) to service_role;

-- Companion function: count + JSON sample so the cron job can emit
-- a single-row result that's grep-able in cron.job_run_details. Real
-- alerting (PagerDuty / Slack) would call this and route on
-- stuck_count > 0; the count + sample shape is so the query result
-- is readable in `cron.job_run_details.return_message`.

create or replace function jobs_stuck_summary(
  p_stuck_after interval default interval '5 minutes'
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'stuck_count',  count(*),
    'oldest_age_s', coalesce(extract(epoch from max(now() - locked_at))::int, 0),
    'sample',       coalesce(
      (select jsonb_agg(
         jsonb_build_object(
           'id',         s.id,
           'kind',       s.kind,
           'locked_by',  s.locked_by,
           'attempts',   s.attempts,
           'age_s',      extract(epoch from s.age)::int
         ) order by s.age desc
       )
       from (
         select * from find_stuck_jobs(p_stuck_after) limit 5
       ) s),
      '[]'::jsonb
    ),
    'checked_at', now()
  )
  from find_stuck_jobs(p_stuck_after);
$$;

revoke execute on function jobs_stuck_summary(interval) from public;
grant execute on function jobs_stuck_summary(interval) to service_role;

-- Schedule every 10 min. Granular enough that an operator notices
-- within ~10 min of a stuck job; not so chatty that idle queues
-- spam cron.job_run_details. Idempotent — cron.schedule with the
-- same name is a no-op on re-run.
select cron.schedule(
  'jobs-stuck-alert',
  '*/10 * * * *',
  $$select public.jobs_stuck_summary()$$
);

-- Public wrapper so tests + future operator dashboards can verify
-- the schedule landed without needing direct cron schema access
-- (PostgREST exposes only `public` + `graphql_public`).
create or replace function cron_schedule_status(p_jobname text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'jobname',  jobname,
    'schedule', schedule,
    'active',   active
  )
  from cron.job
  where jobname = p_jobname;
$$;

revoke execute on function cron_schedule_status(text) from public;
grant execute on function cron_schedule_status(text) to service_role;

