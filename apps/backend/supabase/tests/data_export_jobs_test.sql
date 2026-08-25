-- Pin the async Art 20 export queue from migration
-- 20270603_001_async_data_export.sql.
--
-- The contract the Go worker + the web status endpoint rest on:
--
--   1. `enqueue_data_export` inserts BOTH rows — the durable
--      `data_export_jobs` state row and the `jobs` queue entry — or
--      neither. Two round-trips from the handler could leave a state
--      row nothing will ever build, and the subject then polls forever.
--   2. A second enqueue while one is in flight REUSES the in-flight row
--      and enqueues no second job. Every attempt that reaches the tus
--      Finish uploads a whole archive, so a retried POST must not cost
--      one archive per tap.
--   3. Once the first export leaves flight, a new one may be enqueued —
--      the dedupe is on the in-flight set, not on the subject.
--   4. The queue entry carries max_attempts = 2, not the table default
--      of 5, for the same Storage-cost reason.
--   5. A bad format is refused by the function, not only by the CHECK.
--   6. The one-in-flight unique index is real, so a caller reaching the
--      table directly cannot open a second concurrent export either.
--   7. `expire_stale_export_jobs` (the half of the blob sweep pgtap can
--      reach — storage.objects refuses a direct DELETE locally) expires a
--      `ready` row past the artifact window and leaves a fresh one
--      alone. A row outliving its object keeps offering a 404.
--   8. RLS is on with no policies: the row is unreadable by anon and
--      authenticated. It is useless without a signed URL, which only
--      the service role can mint.

begin;

select plan(19);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000e001', 'authenticated', 'authenticated',
   'subject@export.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000e002', 'authenticated', 'authenticated',
   'other@export.local', '', now(), now());

-- ─────────────── 1. a first enqueue creates both rows ───────────────

create temp table enq1 as
select * from enqueue_data_export(
  '00000000-0000-0000-0000-00000000e001'::uuid, 'backup');

select is(
  (select reused from enq1),
  false,
  'a first enqueue is not a reuse'
);

select is(
  (select status from enq1),
  'queued',
  'a fresh export starts queued'
);

select is(
  (select count(*)::int from data_export_jobs
   where user_id = '00000000-0000-0000-0000-00000000e001'),
  1,
  'one data_export_jobs row exists for the subject'
);

select is(
  (select count(*)::int from jobs
   where kind = 'data_export'
     and (payload->>'export_job_id')::uuid = (select id from enq1)),
  1,
  'one jobs row was enqueued against that export id'
);

select is(
  (select payload->>'format' from jobs
   where kind = 'data_export'
     and (payload->>'export_job_id')::uuid = (select id from enq1)),
  'backup',
  'the queue payload carries the requested format'
);

select is(
  (select payload->>'user_id' from jobs
   where kind = 'data_export'
     and (payload->>'export_job_id')::uuid = (select id from enq1)),
  '00000000-0000-0000-0000-00000000e001',
  'the queue payload carries the subject'
);

-- 4. max_attempts is deliberately below the table default.
select is(
  (select max_attempts::int from jobs
   where kind = 'data_export'
     and (payload->>'export_job_id')::uuid = (select id from enq1)),
  2,
  'an export job gets 2 attempts, not the table default of 5'
);

-- ─────────────── 2. a re-enqueue while in flight reuses ───────────────

create temp table enq2 as
select * from enqueue_data_export(
  '00000000-0000-0000-0000-00000000e001'::uuid, 'csv');

select is(
  (select reused from enq2),
  true,
  'a second enqueue while one is in flight is a reuse'
);

select is(
  (select id from enq2),
  (select id from enq1),
  'the reuse returns the in-flight export, not a new one'
);

select is(
  (select format from enq2),
  'backup',
  'the reuse reports the IN-FLIGHT format, not the one just asked for'
);

select is(
  (select count(*)::int from jobs where kind = 'data_export'),
  1,
  'a reuse enqueues no second queue entry'
);

-- The same reuse must NOT leak across subjects.
select lives_ok(
  $$ select * from enqueue_data_export(
       '00000000-0000-0000-0000-00000000e002'::uuid, 'gpx') $$,
  'a different subject may enqueue while the first is in flight'
);

-- ─────────────── 3. leaving flight frees the slot ───────────────

update data_export_jobs
set status = 'ready',
    object_path = '00000000-0000-0000-0000-00000000e001/exports/x.zip',
    finished_at = now()
where user_id = '00000000-0000-0000-0000-00000000e001';

select isnt(
  (select id from enqueue_data_export(
     '00000000-0000-0000-0000-00000000e001'::uuid, 'csv')),
  (select id from enq1),
  'once the first export is ready, a new enqueue starts a new one'
);

-- ─────────────── 5. a bad format is refused by the function ───────────────

select throws_ok(
  $$ select * from enqueue_data_export(
       '00000000-0000-0000-0000-00000000e002'::uuid, 'pdf') $$,
  '22023',
  null,
  'enqueue_data_export refuses a format outside the allowlist'
);

-- ─────────────── 6. the one-in-flight index binds direct writers ───────────────

select throws_ok(
  $$ insert into data_export_jobs (user_id, format)
     values ('00000000-0000-0000-0000-00000000e002', 'csv') $$,
  '23505',
  null,
  'a direct INSERT cannot open a second in-flight export for a subject'
);

-- ─────────────── 7. retention expires the row with its artifact ───────────────

update data_export_jobs
set status = 'ready',
    object_path = '00000000-0000-0000-0000-00000000e001/exports/old.zip',
    finished_at = now() - interval '8 days'
where user_id = '00000000-0000-0000-0000-00000000e001'
  and status = 'queued';

select expire_stale_export_jobs();

select is(
  (select count(*)::int from data_export_jobs
   where user_id = '00000000-0000-0000-0000-00000000e001'
     and status = 'expired'
     and object_path is null),
  1,
  'a ready row older than the artifact retention window expires with it'
);

select is(
  (select count(*)::int from data_export_jobs
   where user_id = '00000000-0000-0000-0000-00000000e001'
     and status = 'ready'),
  1,
  'a ready row inside the window is left alone'
);

-- ─────────────── 8. RLS is on with no policies ───────────────

-- Asserted structurally rather than by reading as `authenticated`: the
-- claim is that the table has no client read path AT ALL, and a policy
-- added later that happened to deny this particular subject would still
-- pass a row-count assertion. The row is useless without a signed URL,
-- which only the service role can mint, so the entire read goes through
-- the Go worker's JWT-authed status endpoint.
select is(
  (select relrowsecurity from pg_class where oid = 'public.data_export_jobs'::regclass),
  true,
  'data_export_jobs has row level security enabled'
);

select is(
  (select count(*)::int from pg_policies
   where schemaname = 'public' and tablename = 'data_export_jobs'),
  0,
  'data_export_jobs carries no RLS policies, so no client can read it directly'
);

select * from finish();
rollback;
