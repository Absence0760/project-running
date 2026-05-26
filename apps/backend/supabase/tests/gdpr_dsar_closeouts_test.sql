-- Pins the migration 20260928_001 GDPR / DSAR closeouts.
--
-- Three load-bearing artefacts that an audit-aware future contributor
-- might accidentally regress:
--
--   1. `purge-stale-jobs` cron schedule must exist + target the right
--      function. Without it the jobs table accumulates terminal rows
--      forever and the GDPR Art 5(1)(e) retention disclosure in
--      docs/compliance/retention.md becomes a lie.
--   2. `rate_limits.user_id` must FK-cascade to auth.users. Without
--      that, deleting a user leaves rate-limit rows holding the UUID
--      for up to 24h post-deletion.
--   3. `deletion_audit_log.third_party_outcomes` jsonb column must
--      exist + accept the documented shape. The delete-account EF
--      relies on it to satisfy Art 17(2) recipient-notification.

begin;
select plan(6);

-- ─── jobs retention cron ───
select isnt_empty(
  $$select 1 from cron.job where jobname = 'purge-stale-jobs'$$,
  'purge-stale-jobs cron schedule must exist'
);

select is(
  (select command from cron.job where jobname = 'purge-stale-jobs'),
  'select private.purge_stale_jobs()',
  'purge-stale-jobs cron must call private.purge_stale_jobs()'
);

select has_function(
  'private', 'purge_stale_jobs', ARRAY[]::text[],
  'private.purge_stale_jobs() must exist'
);

-- ─── rate_limits FK ───
-- The FK was added in 20260928_001, then rolled back in
-- 20261003_001 because synthetic UUIDs from ipBucketKey() in the
-- anon webhook paths can't satisfy it. The "deleted-uuid survives
-- 24h" gap is now closed by the explicit drain in delete-account.
select is_empty(
  $$select 1 from pg_constraint
      where conname = 'rate_limits_user_id_fkey'$$,
  'rate_limits_user_id_fkey must NOT exist — rolled back per 20261003_001'
);

-- ─── deletion_audit_log.third_party_outcomes ───
select has_column(
  'public', 'deletion_audit_log', 'third_party_outcomes',
  'deletion_audit_log.third_party_outcomes column must exist'
);

select col_type_is(
  'public', 'deletion_audit_log', 'third_party_outcomes', 'jsonb',
  'deletion_audit_log.third_party_outcomes must be jsonb'
);

select * from finish();
rollback;
