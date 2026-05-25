-- audit/gdpr (2026-05-25) Art 5(1)(e) storage-limitation guard.
-- Locks in the three purge functions from
-- 20260922_001_data_retention_purge_jobs.sql so a regression where
-- the cron entries disappear or the cutoff windows are reset
-- silently surfaces here, not in a year's worth of accumulated PII.

begin;

select plan(7);

-- ─── functions exist with the documented signatures ──────────
select has_function(
  'private', 'purge_stale_coach_messages', array[]::text[],
  'private.purge_stale_coach_messages() exists');

select has_function(
  'private', 'purge_stale_notifications', array[]::text[],
  'private.purge_stale_notifications() exists');

select has_function(
  'private', 'purge_stale_device_tokens', array[]::text[],
  'private.purge_stale_device_tokens() exists');

-- ─── cron entries are registered ─────────────────────────────
-- pg_cron stores schedule rows in `cron.job`. We assert one per
-- documented entry so a future migration can't quietly drop the
-- schedule without leaving the function callable but un-fired.
select is(
  (select count(*)::int from cron.job
     where jobname = 'purge-stale-coach-messages'),
  1,
  'pg_cron entry purge-stale-coach-messages is registered'
);

select is(
  (select count(*)::int from cron.job
     where jobname = 'purge-stale-notifications'),
  1,
  'pg_cron entry purge-stale-notifications is registered'
);

select is(
  (select count(*)::int from cron.job
     where jobname = 'purge-stale-device-tokens'),
  1,
  'pg_cron entry purge-stale-device-tokens is registered'
);

-- ─── functional check: an artificially-aged coach_messages row
--     is removed by a manual call. Uses a seed-user fixture so
--     the RLS owner is real; coach_messages requires a non-null
--     user_id.
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000d0001', 'authenticated', 'authenticated',
   'retention@local.test', '', now(), now())
on conflict (id) do nothing;

insert into coach_messages (id, user_id, role, content, created_at)
values
  ('00000000-0000-0000-0000-00000000eeee',
   '00000000-0000-0000-0000-0000000d0001',
   'user',
   'aged out',
   now() - interval '20 months');

select private.purge_stale_coach_messages();

select is(
  (select count(*)::int from coach_messages
     where id = '00000000-0000-0000-0000-00000000eeee'),
  0,
  'purge_stale_coach_messages drops rows older than 18 months'
);

select * from finish();
rollback;
