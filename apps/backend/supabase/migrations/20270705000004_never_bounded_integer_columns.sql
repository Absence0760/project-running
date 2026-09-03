-- The other forty never-bounded numeric columns: the integer family.
--
-- The filing counted 31. Re-derived from the live catalogue, **79** numeric
-- columns in `public` carry no single-column CHECK. Thirty-one are in a type
-- that can hold NaN and are closed by 20270705000001 / 20270705000002; the
-- remaining forty-eight are `smallint` / `integer` / `bigint`, where the value
-- that poisons an aggregate is unreachable at the type but a nonsense SIGN is
-- not. Four of the forty-eight are sequence-backed surrogate keys and take no
-- bound (see the exemption note at the foot); four more — the two ping tables'
-- `bpm` and `elapsed_s` — were taken with their tables in 20270705000001, so
-- forty are left and they are all here.
--
-- ── Why this half is not merely tidiness ───────────────────────────────────
-- 20270704000001 measured the cost of an unbounded time column and it was not
-- theoretical: a negative `runs.duration_s` written over PostgREST with an
-- ordinary password-grant JWT became the account's 5k best. The same shape is
-- still open one column over. `refresh_personal_records` reads the promoted
-- embedded-best columns under the filter
--
--     and fastest_5k_s is not null and fastest_5k_s >= 0
--
-- — `>= 0`, not `> 0` — so a zero-second 5k written to `runs.fastest_5k_s`
-- becomes the account's best 5k and outranks every real effort, and a negative
-- one is refused by the filter only by luck of the sign. The four `fastest_*_s`
-- columns therefore take `> 0` rather than `>= 0`: the constraint is the root
-- fix, and it makes the RPC's own `>= 0` filter equivalent rather than
-- load-bearing. `personal_records.best_time_s` takes `> 0` for the same reason
-- one table over — it IS the PR board.
--
-- Everything else takes the floor its meaning gives it and nothing more:
--
--   >= 0   every count, index, ordinal, position, duration, tolerance and
--          distance. A negative one is impossible, not merely unlikely.
--   >= 1   `event_results.rank`. There is no zeroth place.
--   >  0   the four `runs.fastest_*_s`, `personal_records.best_time_s`,
--          `events.pace_target_sec` (a pace of zero is an infinite speed and
--          a divisor), `training_plans.current_5k_seconds` and
--          `goal_time_seconds` (a zero-second 5k is the same defect as the
--          PR one, one table over, and it seeds the whole plan's VDOT).
--
-- One column here could not be bounded at all until the migration before this
-- one landed. `plan_weeks.week_index` is legitimately negative for the span of
-- two statements inside `duplicate_plan_week`, which hopped the tail of a plan
-- through negative index space to renumber it under a per-row unique
-- constraint. 20270705000003 replaces that with a deferred check, and this
-- migration's `week_index >= 0` would be a 23514 on the plan editor's
-- "duplicate week" button without it — which is why the two are ordered.
--
-- Three deliberate NON-refusals, so the reasoning is on the record rather than
-- looking like an oversight:
--
--   * `events.capacity` admits 0 — a capacity of zero is how an organiser
--     closes registration without deleting the event.
--   * `events.recurrence_count` admits 0 rather than taking the `>= 1` its
--     name suggests: the recurrence helpers treat a missing count as unbounded
--     and nothing in the schema fixes what a stored 0 means, so refusing it
--     would be a claim this migration cannot support.
--   * `event_pricing.sales_close_offset_minutes` takes `>= 0`. It is minutes
--     BEFORE the event when sales close, defaulting to 0 (they close at the
--     start); a negative would push the sales window past the start, which no
--     surface offers.
--
-- ── Online safety (docs/backend/migration_locks.md) ────────────────────────
-- `runs`, `run_photos` and `rate_limits` are in the playbook's high-volume set
-- and `check_migration_online_safety.mjs` enforces the two-step on them. Every
-- table here uses it regardless: each table's constraints are added in ONE
-- `alter table` so it pays a single brief ACCESS EXCLUSIVE for all of its
-- columns, every add is `NOT VALID` (a metadata flip, no scan), and each
-- validation is a separate statement under SHARE UPDATE EXCLUSIVE where readers
-- and writers proceed.
--
-- No repair pass. A negative count has no honest replacement and a zero-second
-- 5k is a bogus personal record that should be investigated, not rewritten to a
-- plausible number. Run these before applying to a populated instance — every
-- one must return 0, or the matching VALIDATE fails:
--
--   select count(*) from runs
--    where fastest_5k_s <= 0 or fastest_10k_s <= 0
--       or fastest_half_marathon_s <= 0 or fastest_marathon_s <= 0;
--   select count(*) from personal_records where best_time_s <= 0;
--   select count(*) from training_plans
--    where current_5k_seconds <= 0 or goal_time_seconds <= 0;
--   select count(*) from events
--    where capacity < 0 or duration_min < 0 or pace_target_sec <= 0
--       or recurrence_count < 0;
--   select count(*) from event_results where rank < 1;
--   select count(*) from app_quota where count < 0;
--   select count(*) from challenges where participant_count < 0;
--   select count(*) from club_photos where position_idx < 0;
--   select count(*) from clubs where member_count < 0;
--   select count(*) from data_export_jobs where run_count < 0 or total_runs < 0;
--   select count(*) from event_checkpoints where ordinal < 0;
--   select count(*) from event_pricing where sales_close_offset_minutes < 0;
--   select count(*) from fitness_snapshots where qualifying_run_count < 0;
--   select count(*) from gym_sets where set_index < 0;
--   select count(*) from gym_workouts where set_count < 0;
--   select count(*) from monthly_funding where donor_count < 0;
--   select count(*) from plan_weeks where week_index < 0;
--   select count(*) from plan_workouts
--    where target_duration_seconds < 0 or target_pace_tolerance_sec < 0;
--   select count(*) from race_listings where distance_m < 0;
--   select count(*) from rate_limits where count < 0;
--   select count(*) from route_photos where position_idx < 0;
--   select count(*) from routes where run_count < 0;
--   select count(*) from run_matched_tracks where attempts < 0;
--   select count(*) from run_photos where position_idx < 0;
--   select count(*) from session_plan_blocks where position < 0;
--   select count(*) from session_plan_items
--    where position < 0 or duration_s < 0 or reps < 0;
--   select count(*) from session_plans where est_duration_min < 0;
--   select count(*) from user_coach_usage where message_count < 0;
--   select count(*) from user_profiles where tier_updated_event_ts < 0;
--
-- ── The four columns that stay unbounded ───────────────────────────────────
-- `deletion_audit_log.id`, `jobs.id`, `live_run_pings.id` and `race_pings.id`
-- are sequence- or identity-backed surrogate keys. Their values come from a
-- sequence that starts at 1 and never decreases, no client supplies one, and a
-- CHECK would be a scan over the largest tables in the schema to prove
-- something the sequence already guarantees. They are registered as exemptions
-- in `numeric_bounds_reject_nan_test.sql` with that reason, so the coverage
-- rule fails on any OTHER unbounded numeric column added later.
--
-- No column type, nullability or default moves, so neither row-type generator
-- has anything to regenerate.

alter table app_quota
  add constraint app_quota_count_check check (count >= 0) not valid;
alter table app_quota validate constraint app_quota_count_check;

alter table challenges
  add constraint challenges_participant_count_check
    check (participant_count >= 0) not valid;
alter table challenges validate constraint challenges_participant_count_check;

alter table club_photos
  add constraint club_photos_position_idx_check
    check (position_idx >= 0) not valid;
alter table club_photos validate constraint club_photos_position_idx_check;

alter table clubs
  add constraint clubs_member_count_check check (member_count >= 0) not valid;
alter table clubs validate constraint clubs_member_count_check;

alter table data_export_jobs
  add constraint data_export_jobs_run_count_check
    check (run_count is null or run_count >= 0) not valid,
  add constraint data_export_jobs_total_runs_check
    check (total_runs is null or total_runs >= 0) not valid;
alter table data_export_jobs validate constraint data_export_jobs_run_count_check;
alter table data_export_jobs validate constraint data_export_jobs_total_runs_check;

alter table event_checkpoints
  add constraint event_checkpoints_ordinal_check check (ordinal >= 0) not valid;
alter table event_checkpoints validate constraint event_checkpoints_ordinal_check;

alter table event_pricing
  add constraint event_pricing_sales_close_offset_minutes_check
    check (sales_close_offset_minutes >= 0) not valid;
alter table event_pricing
  validate constraint event_pricing_sales_close_offset_minutes_check;

alter table event_results
  add constraint event_results_rank_check
    check (rank is null or rank >= 1) not valid;
alter table event_results validate constraint event_results_rank_check;

alter table events
  add constraint events_capacity_check
    check (capacity is null or capacity >= 0) not valid,
  add constraint events_duration_min_check
    check (duration_min is null or duration_min >= 0) not valid,
  add constraint events_pace_target_sec_check
    check (pace_target_sec is null or pace_target_sec > 0) not valid,
  add constraint events_recurrence_count_check
    check (recurrence_count is null or recurrence_count >= 0) not valid;
alter table events validate constraint events_capacity_check;
alter table events validate constraint events_duration_min_check;
alter table events validate constraint events_pace_target_sec_check;
alter table events validate constraint events_recurrence_count_check;

alter table fitness_snapshots
  add constraint fitness_snapshots_qualifying_run_count_check
    check (qualifying_run_count >= 0) not valid;
alter table fitness_snapshots
  validate constraint fitness_snapshots_qualifying_run_count_check;

alter table gym_sets
  add constraint gym_sets_set_index_check check (set_index >= 0) not valid;
alter table gym_sets validate constraint gym_sets_set_index_check;

alter table gym_workouts
  add constraint gym_workouts_set_count_check check (set_count >= 0) not valid;
alter table gym_workouts validate constraint gym_workouts_set_count_check;

alter table monthly_funding
  add constraint monthly_funding_donor_count_check
    check (donor_count >= 0) not valid;
alter table monthly_funding validate constraint monthly_funding_donor_count_check;

alter table personal_records
  add constraint personal_records_best_time_s_check
    check (best_time_s > 0) not valid;
alter table personal_records validate constraint personal_records_best_time_s_check;

alter table plan_weeks
  add constraint plan_weeks_week_index_check check (week_index >= 0) not valid;
alter table plan_weeks validate constraint plan_weeks_week_index_check;

alter table plan_workouts
  add constraint plan_workouts_target_duration_seconds_check
    check (target_duration_seconds is null or target_duration_seconds >= 0) not valid,
  add constraint plan_workouts_target_pace_tolerance_sec_check
    check (target_pace_tolerance_sec is null or target_pace_tolerance_sec >= 0) not valid;
alter table plan_workouts validate constraint plan_workouts_target_duration_seconds_check;
alter table plan_workouts validate constraint plan_workouts_target_pace_tolerance_sec_check;

alter table race_listings
  add constraint race_listings_distance_m_check
    check (distance_m is null or distance_m >= 0) not valid;
alter table race_listings validate constraint race_listings_distance_m_check;

alter table rate_limits
  add constraint rate_limits_count_check check (count >= 0) not valid;
alter table rate_limits validate constraint rate_limits_count_check;

alter table route_photos
  add constraint route_photos_position_idx_check
    check (position_idx >= 0) not valid;
alter table route_photos validate constraint route_photos_position_idx_check;

alter table routes
  add constraint routes_run_count_check check (run_count >= 0) not valid;
alter table routes validate constraint routes_run_count_check;

alter table run_matched_tracks
  add constraint run_matched_tracks_attempts_check
    check (attempts >= 0) not valid;
alter table run_matched_tracks validate constraint run_matched_tracks_attempts_check;

alter table run_photos
  add constraint run_photos_position_idx_check
    check (position_idx >= 0) not valid;
alter table run_photos validate constraint run_photos_position_idx_check;

alter table runs
  add constraint runs_fastest_5k_s_check
    check (fastest_5k_s is null or fastest_5k_s > 0) not valid,
  add constraint runs_fastest_10k_s_check
    check (fastest_10k_s is null or fastest_10k_s > 0) not valid,
  add constraint runs_fastest_half_marathon_s_check
    check (fastest_half_marathon_s is null or fastest_half_marathon_s > 0) not valid,
  add constraint runs_fastest_marathon_s_check
    check (fastest_marathon_s is null or fastest_marathon_s > 0) not valid;
alter table runs validate constraint runs_fastest_5k_s_check;
alter table runs validate constraint runs_fastest_10k_s_check;
alter table runs validate constraint runs_fastest_half_marathon_s_check;
alter table runs validate constraint runs_fastest_marathon_s_check;

alter table session_plan_blocks
  add constraint session_plan_blocks_position_check
    check (position >= 0) not valid;
alter table session_plan_blocks validate constraint session_plan_blocks_position_check;

alter table session_plan_items
  add constraint session_plan_items_position_check
    check (position >= 0) not valid,
  add constraint session_plan_items_duration_s_check
    check (duration_s is null or duration_s >= 0) not valid,
  add constraint session_plan_items_reps_check
    check (reps is null or reps >= 0) not valid;
alter table session_plan_items validate constraint session_plan_items_position_check;
alter table session_plan_items validate constraint session_plan_items_duration_s_check;
alter table session_plan_items validate constraint session_plan_items_reps_check;

alter table session_plans
  add constraint session_plans_est_duration_min_check
    check (est_duration_min is null or est_duration_min >= 0) not valid;
alter table session_plans validate constraint session_plans_est_duration_min_check;

alter table training_plans
  add constraint training_plans_current_5k_seconds_check
    check (current_5k_seconds is null or current_5k_seconds > 0) not valid,
  add constraint training_plans_goal_time_seconds_check
    check (goal_time_seconds is null or goal_time_seconds > 0) not valid;
alter table training_plans validate constraint training_plans_current_5k_seconds_check;
alter table training_plans validate constraint training_plans_goal_time_seconds_check;

alter table user_coach_usage
  add constraint user_coach_usage_message_count_check
    check (message_count >= 0) not valid;
alter table user_coach_usage validate constraint user_coach_usage_message_count_check;

alter table user_profiles
  add constraint user_profiles_tier_updated_event_ts_check
    check (tier_updated_event_ts is null or tier_updated_event_ts >= 0) not valid;
alter table user_profiles
  validate constraint user_profiles_tier_updated_event_ts_check;
