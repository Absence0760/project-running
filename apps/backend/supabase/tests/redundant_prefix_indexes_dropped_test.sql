-- Pins the redundant-prefix-index cleanup (migration 20270423_001).
--
-- Each of the six redundant indexes was an exact left-prefix of a UNIQUE / PK
-- index on the same table, so dropping it loses no query capability. This test
-- asserts, per index: (1) the redundant index is GONE, and (2) its covering
-- unique/PK index still EXISTS — so the left-prefix access path is preserved.
-- Fails before the migration (redundant index present), passes after.

begin;

select plan(13);

create or replace function pg_temp.idx_exists(idx text)
returns boolean language sql stable as $fn$
  select exists (
    select 1 from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'i' and c.relname = idx
  );
$fn$;

-- event_checkpoints: (event_id, ordinal)
select ok(not pg_temp.idx_exists('event_checkpoints_event'),
  'event_checkpoints_event dropped');
select ok(pg_temp.idx_exists('event_checkpoints_event_id_ordinal_key'),
  'covering unique event_checkpoints_event_id_ordinal_key remains');

-- plan_weeks: (plan_id, week_index)
select ok(not pg_temp.idx_exists('plan_weeks_plan'),
  'plan_weeks_plan dropped');
select ok(pg_temp.idx_exists('plan_weeks_plan_id_week_index_key'),
  'covering unique plan_weeks_plan_id_week_index_key remains');

-- plan_workouts: (week_id, scheduled_date)
select ok(not pg_temp.idx_exists('plan_workouts_week'),
  'plan_workouts_week dropped');
select ok(pg_temp.idx_exists('plan_workouts_one_per_day'),
  'covering unique plan_workouts_one_per_day remains');

-- event_exceptions: (event_id) ⊂ pk (event_id, instance_start)
select ok(not pg_temp.idx_exists('event_exceptions_event'),
  'event_exceptions_event dropped');
select ok(pg_temp.idx_exists('event_exceptions_pkey'),
  'covering pk event_exceptions_pkey remains');

-- event_result_claims: (result_id) ⊂ unique (result_id, claimant_id)
select ok(not pg_temp.idx_exists('event_result_claims_by_result'),
  'event_result_claims_by_result dropped');
select ok(pg_temp.idx_exists('event_result_claims_result_id_claimant_id_key'),
  'covering unique event_result_claims_result_id_claimant_id_key remains');
-- The partial pending index is a different predicate, not redundant: keep it.
select ok(pg_temp.idx_exists('event_result_claims_pending'),
  'partial event_result_claims_pending is untouched');

-- user_device_settings: (user_id) ⊂ pk (user_id, device_id)
select ok(not pg_temp.idx_exists('user_device_settings_by_user'),
  'user_device_settings_by_user dropped');
select ok(pg_temp.idx_exists('user_device_settings_pkey'),
  'covering pk user_device_settings_pkey remains');

select * from finish();

rollback;
