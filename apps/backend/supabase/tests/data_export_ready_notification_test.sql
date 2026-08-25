-- Pin the data-export-ready announcement from migration
-- 20270607_001_data_export_ready_notification.sql (decisions.md § 729).
--
-- The contract the Go worker's completion hook rests on:
--
--   1. `notifications.kind` accepts the new `data_export_ready` value —
--      the CHECK widen and the Go/TS kind tables have to agree or the
--      insert dies at 23514 inside a SECURITY DEFINER function whose
--      caller has already finished the export.
--   2. A ready export announces exactly once: one inbox row for its own
--      subject, `notified_at` stamped in the same statement.
--   3. A SECOND call announces nothing. `data_export` jobs carry
--      max_attempts = 2 and the queue is at-least-once regardless, so a
--      redelivery after a successful build must be silent.
--   4. A row that is not ready, or is ready with no `object_path`, or has
--      expired, announces nothing. Each is a state in which there is
--      nothing to collect, and an announcement would send the subject to
--      a download that is not there.
--   5. The function is service_role only. The notifications AFTER INSERT
--      fan-out turns every row into an email job and a push job, so a
--      client-reachable version is a mail cannon.
--   6. The announcement rides the existing rail: the fan-out enqueued a
--      `notification_email` job for the row, exactly as it does for every
--      other kind.

begin;

select plan(14);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000f001', 'authenticated', 'authenticated',
   'subject@exportready.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000f002', 'authenticated', 'authenticated',
   'other@exportready.local', '', now(), now());

-- ─────────────── 1. the kind is storable ───────────────

select lives_ok(
  $$ insert into notifications (user_id, kind)
     values ('00000000-0000-0000-0000-00000000f001', 'data_export_ready') $$,
  'notifications accepts kind = ''data_export_ready'''
);

delete from notifications
where user_id = '00000000-0000-0000-0000-00000000f001';
delete from jobs where kind = 'notification_email';

-- ─────────────── 2. a ready export announces once ───────────────

insert into data_export_jobs (id, user_id, format, status, object_path, finished_at)
values (
  '00000000-0000-0000-0000-0000000000a1',
  '00000000-0000-0000-0000-00000000f001',
  'backup', 'ready',
  '00000000-0000-0000-0000-00000000f001/2026-08-25T10-00-00.000Z.zip',
  now()
);

select is(
  notify_data_export_ready('00000000-0000-0000-0000-0000000000a1'),
  true,
  'a ready export with an artifact announces'
);

select is(
  (select count(*)::int from notifications
   where user_id = '00000000-0000-0000-0000-00000000f001'
     and kind = 'data_export_ready'),
  1,
  'exactly one inbox row was written'
);

select isnt(
  (select notified_at from data_export_jobs
   where id = '00000000-0000-0000-0000-0000000000a1'),
  null,
  'the export row is stamped notified_at in the same statement'
);

-- The announcement carries no FK: the export has no row in any table a
-- notification can point at, and both deep-link tables send this kind to
-- /settings/account, where the signed URL is minted at read time.
select ok(
  (select run_id is null and event_id is null and club_id is null
          and comment_id is null and actor_id is null
   from notifications
   where user_id = '00000000-0000-0000-0000-00000000f001'
     and kind = 'data_export_ready'),
  'the announcement carries no source FK and no actor'
);

-- ─────────────── 3. it rides the existing email fan-out ───────────────

select is(
  (select count(*)::int from jobs
   where kind = 'notification_email'
     and (payload->>'notification_id')::uuid = (
       select id from notifications
       where user_id = '00000000-0000-0000-0000-00000000f001'
         and kind = 'data_export_ready')),
  1,
  'the notifications AFTER INSERT fan-out enqueued a notification_email job'
);

-- ─────────────── 4. a redelivery announces nothing ───────────────

select is(
  notify_data_export_ready('00000000-0000-0000-0000-0000000000a1'),
  false,
  'a second call on an already-announced export refuses'
);

select is(
  (select count(*)::int from notifications
   where user_id = '00000000-0000-0000-0000-00000000f001'
     and kind = 'data_export_ready'),
  1,
  'the redelivery wrote no second inbox row'
);

-- ─────────────── 5. the states with nothing to collect ───────────────

insert into data_export_jobs (id, user_id, format, status)
values (
  '00000000-0000-0000-0000-0000000000a2',
  '00000000-0000-0000-0000-00000000f002',
  'backup', 'running'
);

select is(
  notify_data_export_ready('00000000-0000-0000-0000-0000000000a2'),
  false,
  'an export still building announces nothing'
);

-- Ready but pathless: the row's whole claim is that an artifact exists,
-- and without the path there is nothing to sign at read time.
update data_export_jobs
set status = 'ready', object_path = null, finished_at = now()
where id = '00000000-0000-0000-0000-0000000000a2';

select is(
  notify_data_export_ready('00000000-0000-0000-0000-0000000000a2'),
  false,
  'a ready export carrying no object_path announces nothing'
);

-- `expire_stale_export_jobs` flips a ready row to expired and nulls its
-- path once the 7-day sweep has taken the artifact. A worker that comes
-- back late must be refused here, not announce a download that 404s.
update data_export_jobs
set status = 'expired'
where id = '00000000-0000-0000-0000-0000000000a2';

select is(
  notify_data_export_ready('00000000-0000-0000-0000-0000000000a2'),
  false,
  'an expired export announces nothing'
);

select is(
  (select count(*)::int from notifications
   where user_id = '00000000-0000-0000-0000-00000000f002'),
  0,
  'the second subject was never told anything'
);

select is(
  notify_data_export_ready('00000000-0000-0000-0000-0000000000ff'),
  false,
  'an export id that is not there announces nothing'
);

-- ─────────────── 6. service_role only ───────────────

select ok(
  not has_function_privilege('anon', 'public.notify_data_export_ready(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.notify_data_export_ready(uuid)', 'EXECUTE'),
  'notify_data_export_ready is not executable by anon or authenticated'
);

select * from finish();
rollback;
