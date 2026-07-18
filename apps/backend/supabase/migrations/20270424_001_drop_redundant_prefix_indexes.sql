-- Drop six btree indexes that are exact left-prefixes of an existing UNIQUE /
-- PRIMARY KEY index on the same table. Each was a manual `create index` that
-- duplicates the leading columns (same order, no partial predicate) of a
-- uniqueness index Postgres already maintains, so it carries write-path
-- maintenance + storage/bloat for zero query benefit: any lookup the redundant
-- index could serve is served by the wider unique index's left prefix.
--
-- Verified live against a fresh `supabase db reset` (pg_indexes): for each drop
-- the covering index is named in the comment and remains after this migration.
-- A plain DROP INDEX takes only a brief lock and is fast; safe inside the
-- transaction Supabase wraps each migration in (CONCURRENTLY is not needed and
-- could not run in a txn anyway).

-- (event_id, ordinal) ⊂ unique event_checkpoints_event_id_ordinal_key (event_id, ordinal)
drop index if exists event_checkpoints_event;

-- (plan_id, week_index) ⊂ unique plan_weeks_plan_id_week_index_key (plan_id, week_index)
drop index if exists plan_weeks_plan;

-- (week_id, scheduled_date) ⊂ unique plan_workouts_one_per_day (week_id, scheduled_date)
drop index if exists plan_workouts_week;

-- (event_id) ⊂ pk event_exceptions_pkey (event_id, instance_start)
drop index if exists event_exceptions_event;

-- (result_id) ⊂ unique event_result_claims_result_id_claimant_id_key (result_id, claimant_id).
-- The partial event_result_claims_pending (result_id) WHERE status = 'pending' is
-- NOT redundant (different predicate) and is intentionally left in place.
drop index if exists event_result_claims_by_result;

-- (user_id) ⊂ pk user_device_settings_pkey (user_id, device_id)
drop index if exists user_device_settings_by_user;
