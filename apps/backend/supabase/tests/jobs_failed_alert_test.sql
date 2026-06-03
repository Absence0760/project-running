-- Pins the failed-job alerting from 20261201_001_jobs_failed_alert.sql:
--   * defer_job re-queues while retry budget remains, but lands an
--     exhausted retry in status='failed' (the previously-invisible
--     "stuck in queued forever" class).
--   * find_failed_jobs returns recent failures and excludes done /
--     queued / running / stale-failed rows.
--   * jobs_failed_summary reports the count + per-kind breakdown.
--   * the jobs-failed-alert pg_cron schedule landed and is active.

begin;

select plan(13);

-- ── defer_job: below the ceiling re-queues ──────────────────────
-- max_attempts default is 5. Simulate a worker that claimed once
-- (attempts=1) then hit a transient error.
insert into public.jobs (kind, payload, status, attempts, locked_by, locked_at)
  values ('map_match', '{}'::jsonb, 'running', 1, 'worker-a', now());
select is(
  defer_job(
    currval(pg_get_serial_sequence('public.jobs', 'id')),
    30,
    'transient: connection reset'
  ),
  'queued',
  'defer_job returns ''queued'' while attempts < max_attempts'
);
select is(
  (select status from public.jobs
   where id = currval(pg_get_serial_sequence('public.jobs', 'id'))),
  'queued',
  'defer_job re-queues while attempts < max_attempts'
);
select ok(
  (select scheduled_at > now() from public.jobs
   where id = currval(pg_get_serial_sequence('public.jobs', 'id'))),
  'defer_job pushes scheduled_at into the future for the retry'
);
select is(
  (select locked_by from public.jobs
   where id = currval(pg_get_serial_sequence('public.jobs', 'id'))),
  null,
  'defer_job clears the lock so another worker can re-claim'
);

-- ── defer_job: at the ceiling fails terminally ──────────────────
-- attempts has reached max_attempts (the claim that just ran was the
-- last one the budget allowed). Re-queuing would strand it forever.
insert into public.jobs (kind, payload, status, attempts, max_attempts, locked_by, locked_at)
  values ('strava_event',
          jsonb_build_object('owner_id', 1, 'object_id', 2,
                             'aspect_type', 'create', 'event_time', 0),
          'running', 5, 5, 'worker-b', now());
select is(
  defer_job(
    currval(pg_get_serial_sequence('public.jobs', 'id')),
    30,
    'transient after exhausting retries'
  ),
  'failed',
  'defer_job returns ''failed'' when the retry budget is exhausted'
);
select is(
  (select status from public.jobs
   where id = currval(pg_get_serial_sequence('public.jobs', 'id'))),
  'failed',
  'defer_job fails an exhausted retry instead of re-queuing it'
);
select ok(
  (select finished_at is not null from public.jobs
   where id = currval(pg_get_serial_sequence('public.jobs', 'id'))),
  'an exhausted-retry failure stamps finished_at'
);
select is(
  (select last_error from public.jobs
   where id = currval(pg_get_serial_sequence('public.jobs', 'id'))),
  'transient after exhausting retries',
  'the exhausted-retry failure preserves last_error'
);

-- ── find_failed_jobs windowing ──────────────────────────────────
-- A fresh failure is in-window; a 1-hour-old failure is out.
insert into public.jobs (kind, payload, status, attempts, finished_at, last_error)
  values ('token_refresh', '{}'::jsonb, 'failed', 3, now(), 'recent boom');
insert into public.jobs (kind, payload, status, attempts, finished_at, last_error)
  values ('token_refresh', '{}'::jsonb, 'failed', 3, now() - interval '1 hour', 'old boom');
-- A done row and a queued row must never show up.
insert into public.jobs (kind, payload, status, finished_at)
  values ('map_match', '{}'::jsonb, 'done', now());
insert into public.jobs (kind, payload, status)
  values ('map_match', '{}'::jsonb, 'queued');

select ok(
  exists(select 1 from find_failed_jobs(interval '15 minutes')
         where last_error = 'recent boom'),
  'find_failed_jobs returns a failure inside the window'
);
select ok(
  not exists(select 1 from find_failed_jobs(interval '15 minutes')
             where last_error = 'old boom'),
  'find_failed_jobs excludes a failure older than the window'
);
select ok(
  not exists(select 1 from find_failed_jobs(interval '15 minutes')
             where kind = 'map_match'),
  'find_failed_jobs excludes done + queued rows (map_match here)'
);

-- ── jobs_failed_summary shape ───────────────────────────────────
-- In-window failures so far: the exhausted strava_event + the recent
-- token_refresh = 2.
select is(
  (jobs_failed_summary(interval '15 minutes') ->> 'failed_count')::int,
  2,
  'jobs_failed_summary counts only in-window failures'
);

-- ── the alert schedule landed ───────────────────────────────────
select is(
  cron_schedule_status('jobs-failed-alert') ->> 'active',
  'true',
  'the jobs-failed-alert pg_cron schedule is registered and active'
);

select * from finish();
rollback;
