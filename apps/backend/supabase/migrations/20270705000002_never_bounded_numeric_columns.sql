-- The rest of the never-bounded NaN-capable columns.
--
-- 20270705000001 took the eleven an anonymous spectator can read. This takes
-- the remaining twenty-one of the thirty-one `numeric` / `double precision`
-- columns in `public` that carried no CHECK at all, leaving `segments.length_m`
-- as the one deliberate exemption (see below).
--
-- ── What "31" counts, and what it does not ─────────────────────────────────
-- Re-derived from the live catalogue rather than taken from the filing: **79**
-- numeric columns in `public` carry no single-column CHECK. Thirty-one of them
-- are in a type that can hold NaN, and those are what this migration and its
-- predecessor close. The other forty-eight are integer-family — a smallint,
-- integer or bigint cannot hold NaN or an infinity at all, so their exposure is
-- a nonsense sign or magnitude rather than a value that poisons an aggregate.
-- They are a weaker class and are closed separately in 20270705000003.
--
-- ── Why an unbounded numeric column is not merely untidy ───────────────────
-- A NaN is absorbing under every aggregate and outranks every real value in a
-- descending sort, which is exactly how each of these columns is consumed:
--
--   * `challenge_badges.final_value` is the number a completed challenge's
--     badge displays forever. NaN there is a permanent wrong answer on a
--     shared surface.
--   * `achievements.value_num` is the figure behind a badge tier, read by
--     `evaluateBadges`' consumers and exported under Art 20.
--   * `fitness_snapshots.vo2_max` / `vdot` / the two loads drive the Fitness
--     card and `selfLoad`'s ACWR; the client computes the ratio and a NaN
--     numerator makes every band unreachable.
--   * `routes.distance_m` is the sort key of the routes list and the input to
--     `distance_bands`; `gym_workouts.volume_kg` is the `/gym` list's headline
--     number and a derived cache; `monthly_funding.amount_received` is money.
--   * the four `position_m` columns place a marker along a course. NaN sorts
--     LAST under `sortMarkers`' nulls-last ordering rather than being treated
--     as missing, so a roadbook silently gains a checkpoint at the end.
--
-- ── The bounds ─────────────────────────────────────────────────────────────
-- Every quantity that cannot be negative takes the one-sided `>= 0` plus the
-- explicit non-finite terms, matching `runs_distance_m_check`: `>= 0` alone
-- says nothing about NaN, and `-Infinity` is the one non-finite value the
-- lower edge does exclude on its own. `<> 'Infinity'` is written only where the
-- type can hold one — a `numeric(p, s)` refuses an infinity with a 22003 field
-- overflow before any CHECK is consulted, so the term would be dead on the
-- scaled columns and is omitted there.
--
-- Two columns are not that shape, and both are deliberate:
--
--   * `fitness_snapshots.training_stress_bal` is chronic minus acute load and
--     is legitimately negative — a runner mid-build has a negative TSB and that
--     is the reading the card exists to show. It therefore gets a pure
--     FINITENESS constraint and no range claim at all. `numeric(8, 2)` already
--     bounds its magnitude at 999999.99 and no honest tighter number exists.
--   * `checkpoint_crossings.body_weight_pct` is the WS100-style weigh-in
--     figure. The repository does not fix its sign convention anywhere — no
--     client computes it, both platforms pass the operator's typed value
--     straight to `upsert_checkpoint_crossing` — so the bound admits both
--     readings: a percent CHANGE (negative for the loss a medical hold is
--     called on) and a percent OF baseline. -100..200 is the widest range
--     either reading can produce from a body weight the sibling column already
--     bounds at 20..400 kg, and it excludes NaN for free by having two sides.
--
-- `vdot` and `vo2_max` cap at 100 on both tables. The shipped client is already
-- stricter — `vdotFromRun` returns null above 90, calling it physiologically
-- impossible — so the column is deliberately WIDER than the writer that feeds
-- it: a bound narrower than a shipped client's own output is a 23514 the user
-- cannot act on, which is the trap decisions § 792 records.
--
-- ── The one exemption: `segments.length_m` ─────────────────────────────────
-- It is `generated always as (end_distance_m - start_distance_m) stored`, so no
-- client writes it, and both operands carry `>= 0 and <> 'NaN' and <>
-- 'Infinity'` since 20270704000002. A finite minus a finite is finite, and
-- `segments_check1` already requires the difference to be at least 100. There
-- is nothing left for a CHECK here to refuse. It is registered as an exemption
-- in `numeric_bounds_reject_nan_test.sql` with that reason rather than left
-- silently uncovered.
--
-- ── Online safety (docs/backend/migration_locks.md) ────────────────────────
-- None of these tables is in the playbook's high-volume set, so the two-step is
-- ceremony here rather than safety — but `routes`, `gym_workouts`,
-- `fitness_snapshots` and `checkpoint_crossings` all grow with usage, and the
-- form is never wrong. Each table's constraints are added in ONE `alter table`
-- so a table pays a single brief ACCESS EXCLUSIVE for all of its columns, every
-- add is `NOT VALID`, and each validation is a separate statement under SHARE
-- UPDATE EXCLUSIVE.
--
-- No repair pass, for the reason 20270704000001 and 20270704000002 give: a NaN
-- has no honest replacement. Run these before applying to a populated instance
-- — every one must return 0, or the matching VALIDATE fails:
--
--   select count(*) from achievements
--    where value_num is not null
--      and (value_num < 0 or value_num in ('NaN', 'Infinity'));
--   select count(*) from challenge_badges
--    where final_value < 0 or final_value in ('NaN', 'Infinity');
--   select count(*) from checkpoint_crossings
--    where body_weight_pct is not null
--      and body_weight_pct not between -100 and 200;
--   select count(*) from event_checkpoints
--    where position_m is not null and (position_m < 0 or position_m = 'NaN');
--   select count(*) from events
--    where distance_m is not null and (distance_m < 0 or distance_m = 'NaN');
--   select count(*) from fitness_snapshots
--    where (acute_load is not null and (acute_load < 0 or acute_load = 'NaN'))
--       or (chronic_load is not null and (chronic_load < 0 or chronic_load = 'NaN'))
--       or (training_stress_bal = 'NaN')
--       or (vdot is not null and vdot not between 0 and 100)
--       or (vo2_max is not null and vo2_max not between 0 and 100);
--   select count(*) from global_segments
--    where elevation_m is not null
--      and (elevation_m < 0 or elevation_m in ('NaN', 'Infinity'));
--   select count(*) from gym_workouts
--    where volume_kg < 0 or volume_kg in ('NaN', 'Infinity');
--   select count(*) from monthly_funding
--    where amount_received < 0 or amount_received = 'NaN';
--   select count(*) from plan_weeks
--    where target_volume_m is not null
--      and (target_volume_m < 0 or target_volume_m = 'NaN');
--   select count(*) from plan_workouts
--    where target_distance_m is not null
--      and (target_distance_m < 0 or target_distance_m = 'NaN');
--   select count(*) from route_conditions
--    where position_m is not null and (position_m < 0 or position_m = 'NaN');
--   select count(*) from route_markers
--    where position_m is not null and (position_m < 0 or position_m = 'NaN');
--   select count(*) from routes
--    where distance_m < 0 or distance_m = 'NaN'
--       or (elevation_m is not null and (elevation_m < 0 or elevation_m = 'NaN'));
--   select count(*) from training_plans
--    where goal_distance_m < 0 or goal_distance_m = 'NaN'
--       or (vdot is not null and vdot not between 0 and 100);
--
-- No column type, nullability or default moves, so neither row-type generator
-- has anything to regenerate.

alter table achievements
  add constraint achievements_value_num_check
    check (value_num is null
           or (value_num >= 0
               and value_num <> 'NaN'::float8
               and value_num <> 'Infinity'::float8)) not valid;

alter table achievements validate constraint achievements_value_num_check;

alter table challenge_badges
  add constraint challenge_badges_final_value_check
    check (final_value >= 0
           and final_value <> 'NaN'::numeric
           and final_value <> 'Infinity'::numeric) not valid;

alter table challenge_badges validate constraint challenge_badges_final_value_check;

alter table checkpoint_crossings
  add constraint checkpoint_crossings_body_weight_pct_check
    check (body_weight_pct is null
           or (body_weight_pct >= -100 and body_weight_pct <= 200)) not valid;

alter table checkpoint_crossings
  validate constraint checkpoint_crossings_body_weight_pct_check;

alter table event_checkpoints
  add constraint event_checkpoints_position_m_check
    check (position_m is null
           or (position_m >= 0 and position_m <> 'NaN'::numeric)) not valid;

alter table event_checkpoints validate constraint event_checkpoints_position_m_check;

alter table events
  add constraint events_distance_m_check
    check (distance_m is null
           or (distance_m >= 0 and distance_m <> 'NaN'::numeric)) not valid;

alter table events validate constraint events_distance_m_check;

alter table fitness_snapshots
  add constraint fitness_snapshots_acute_load_check
    check (acute_load is null
           or (acute_load >= 0 and acute_load <> 'NaN'::numeric)) not valid,
  add constraint fitness_snapshots_chronic_load_check
    check (chronic_load is null
           or (chronic_load >= 0 and chronic_load <> 'NaN'::numeric)) not valid,
  add constraint fitness_snapshots_training_stress_bal_check
    check (training_stress_bal is null
           or training_stress_bal <> 'NaN'::numeric) not valid,
  add constraint fitness_snapshots_vdot_check
    check (vdot is null or (vdot >= 0 and vdot <= 100)) not valid,
  add constraint fitness_snapshots_vo2_max_check
    check (vo2_max is null or (vo2_max >= 0 and vo2_max <= 100)) not valid;

alter table fitness_snapshots validate constraint fitness_snapshots_acute_load_check;
alter table fitness_snapshots validate constraint fitness_snapshots_chronic_load_check;
alter table fitness_snapshots validate constraint fitness_snapshots_training_stress_bal_check;
alter table fitness_snapshots validate constraint fitness_snapshots_vdot_check;
alter table fitness_snapshots validate constraint fitness_snapshots_vo2_max_check;

alter table global_segments
  add constraint global_segments_elevation_m_check
    check (elevation_m is null
           or (elevation_m >= 0
               and elevation_m <> 'NaN'::numeric
               and elevation_m <> 'Infinity'::numeric)) not valid;

alter table global_segments validate constraint global_segments_elevation_m_check;

alter table gym_workouts
  add constraint gym_workouts_volume_kg_check
    check (volume_kg >= 0
           and volume_kg <> 'NaN'::numeric
           and volume_kg <> 'Infinity'::numeric) not valid;

alter table gym_workouts validate constraint gym_workouts_volume_kg_check;

alter table monthly_funding
  add constraint monthly_funding_amount_received_check
    check (amount_received >= 0 and amount_received <> 'NaN'::numeric) not valid;

alter table monthly_funding validate constraint monthly_funding_amount_received_check;

alter table plan_weeks
  add constraint plan_weeks_target_volume_m_check
    check (target_volume_m is null
           or (target_volume_m >= 0 and target_volume_m <> 'NaN'::numeric)) not valid;

alter table plan_weeks validate constraint plan_weeks_target_volume_m_check;

alter table plan_workouts
  add constraint plan_workouts_target_distance_m_check
    check (target_distance_m is null
           or (target_distance_m >= 0
               and target_distance_m <> 'NaN'::numeric)) not valid;

alter table plan_workouts validate constraint plan_workouts_target_distance_m_check;

alter table route_conditions
  add constraint route_conditions_position_m_check
    check (position_m is null
           or (position_m >= 0 and position_m <> 'NaN'::numeric)) not valid;

alter table route_conditions validate constraint route_conditions_position_m_check;

alter table route_markers
  add constraint route_markers_position_m_check
    check (position_m is null
           or (position_m >= 0 and position_m <> 'NaN'::numeric)) not valid;

alter table route_markers validate constraint route_markers_position_m_check;

alter table routes
  add constraint routes_distance_m_check
    check (distance_m >= 0 and distance_m <> 'NaN'::numeric) not valid,
  add constraint routes_elevation_m_check
    check (elevation_m is null
           or (elevation_m >= 0 and elevation_m <> 'NaN'::numeric)) not valid;

alter table routes validate constraint routes_distance_m_check;
alter table routes validate constraint routes_elevation_m_check;

alter table training_plans
  add constraint training_plans_goal_distance_m_check
    check (goal_distance_m >= 0 and goal_distance_m <> 'NaN'::numeric) not valid,
  add constraint training_plans_vdot_check
    check (vdot is null or (vdot >= 0 and vdot <= 100)) not valid;

alter table training_plans validate constraint training_plans_goal_distance_m_check;
alter table training_plans validate constraint training_plans_vdot_check;
