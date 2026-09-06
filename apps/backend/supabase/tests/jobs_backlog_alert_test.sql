-- The third job alert, and the hole in the other two it exists to fill
-- (20270710000004, decisions § 1234).
--
-- `find_stuck_jobs` selects `status = 'running' and locked_at is not null`.
-- `find_failed_jobs` selects `status = 'failed'`. A job no worker ever CLAIMED
-- is `queued` with a null `locked_at`, so it is in neither set -- and a worker
-- that is down produces nothing else. Both alerts therefore report a healthy
-- queue, every ten minutes, for as long as nothing is draining it. That is not
-- an export-retention problem: `safety_sms` carries the overdue-runner
-- escalation to a trusted contact and `data_export` is Art 20 fulfilment.
--
-- Assertion (7) is the one that would have caught it: the same job, read by all
-- three summaries at once.
--
-- The seeded queue is cleared first. `seed.sql` files 87 jobs and no worker
-- runs against a test database, so every one of them is legitimately
-- backlogged; without the clear the counts below would be "87 plus whatever
-- this file filed", which is not an assertion about anything. The whole file
-- is a rolled-back transaction.

begin;

select plan(9);

delete from jobs;

-- The `web_push` row is the shape `defer_job` leaves behind: filed hours ago,
-- pushed forward on a retry. Its `created_at` is deliberately old, or assertion
-- (3) could not tell the two clocks apart -- a job created and deferred in the
-- same instant is excluded by either reading.
insert into jobs (kind, payload, status, scheduled_at, created_at) values
  ('safety_sms', '{}'::jsonb, 'queued', now() - interval '6 hours', now() - interval '6 hours'),
  ('data_export', '{}'::jsonb, 'queued', now() - interval '3 hours', now() - interval '3 hours'),
  ('map_match', '{}'::jsonb, 'queued', now() - interval '2 minutes', now() - interval '2 minutes'),
  ('web_push', '{}'::jsonb, 'queued', now() + interval '4 hours', now() - interval '8 hours');

update jobs set status = 'running', locked_at = now() - interval '9 hours', locked_by = 'w1'
 where kind = 'map_match';

insert into jobs (kind, payload, status, scheduled_at, finished_at, attempts, last_error)
values ('native_push', '{}'::jsonb, 'failed', now() - interval '8 hours',
        now() - interval '1 minute', 5, 'upstream 500');

-- (1) Only the two queued jobs older than the threshold, oldest first.
select results_eq(
  $$ select kind from find_backlogged_jobs('1 hour'::interval) $$,
  $$ values ('safety_sms'::text), ('data_export'::text) $$,
  'a queued job nobody has claimed is backlogged once it is past the threshold, oldest first');

-- (2) The threshold is a threshold. At six hours the three-hour job drops out.
select results_eq(
  $$ select kind from find_backlogged_jobs('5 hours'::interval) $$,
  $$ values ('safety_sms'::text) $$,
  'and the interval argument narrows it rather than being decorative');

-- (3) A job scheduled into the future is DEFERRED, not backlogged. `defer_job`
-- pushes `scheduled_at` forward on a retry, so measuring from `created_at`
-- would report every backing-off job as a stalled queue.
select is(
  (select count(*)::int from find_backlogged_jobs('1 hour'::interval)
    where kind = 'web_push'),
  0,
  'a job scheduled into the future is not backlogged -- the clock is scheduled_at, not created_at');

-- (4) and (5) The three alerts partition the queue rather than overlapping. A
-- claimed-but-wedged job belongs to the stuck alert and a terminally failed one
-- to the failed alert; either appearing here would make a dead worker and a
-- broken handler read the same.
select is(
  (select count(*)::int from find_backlogged_jobs('1 hour'::interval)
    where kind = 'map_match'),
  0,
  'a running job is the stuck alert''s business, not the backlog''s');

select is(
  (select count(*)::int from find_backlogged_jobs('1 hour'::interval)
    where kind = 'native_push'),
  0,
  'and a failed job is the failed alert''s');

-- (6) The summary the scraper actually reads.
select results_eq(
  $$ select (jobs_backlog_summary('1 hour'::interval) ->> 'backlogged_count')::int,
            (jobs_backlog_summary('1 hour'::interval) -> 'by_kind') $$,
  $$ values (2, '{"safety_sms": 1, "data_export": 1}'::jsonb) $$,
  'the summary reports the count and the per-kind breakdown the scraper routes on');

select cmp_ok(
  (jobs_backlog_summary('1 hour'::interval) ->> 'oldest_age_s')::int,
  '>=',
  6 * 3600,
  'and the age of the oldest, so a scraper can alert on duration rather than on presence');

-- (7) The gap, stated as one assertion. The same queued `safety_sms` job read
-- by all three summaries: invisible to the two that existed, visible to this
-- one. Before 20270710000004 the first two figures were the whole picture.
select results_eq(
  $$ select (jobs_stuck_summary('5 minutes'::interval) ->> 'stuck_count')::int,
            (jobs_failed_summary('15 minutes'::interval) ->> 'failed_count')::int,
            (jobs_backlog_summary('1 hour'::interval) ->> 'backlogged_count')::int $$,
  $$ values (1, 1, 2) $$,
  'each alert sees its own third of the queue -- and the two that existed report one job each while two sit unclaimed');

-- (8) An empty queue reports zero rather than null, so a scraper reading
-- `backlogged_count > 0` is not comparing against a null every healthy run.
delete from jobs;
select results_eq(
  $$ select (jobs_backlog_summary() ->> 'backlogged_count')::int,
            (jobs_backlog_summary() ->> 'oldest_age_s')::int,
            (jobs_backlog_summary() -> 'sample') $$,
  $$ values (0, 0, '[]'::jsonb) $$,
  'a drained queue reports zero and an empty sample, never null');

select * from finish();
rollback;
