-- Every one-sided numeric bound in the schema admitted NaN.
--
-- `'NaN'::numeric >= 0` is TRUE, and so is `'NaN'::float8 >= 0` — Postgres
-- orders NaN above every real value in both types rather than treating a
-- comparison with it as unknown. A CHECK written as `col >= 0` therefore says
-- nothing at all about NaN, and 26 of them across eleven tables were exactly
-- that shape. A two-sided bound is immune for free (`NaN <= 500` is false), so
-- `body_metrics.weight_kg`, the two lat/lng pairs, the RPE and percent-of-1RM
-- caps and the weigh-in range were never exposed; the one-sided ones all were.
--
-- Measured by evaluating each constraint's own `pg_get_expr` body with its
-- column substituted for `'NaN'` — not by reading the SQL and agreeing it
-- looks fine. `numeric_bounds_reject_nan_test.sql` runs that same evaluation
-- over the live catalogue on every pgtap run, so a bound added later in the
-- one-sided shape fails the job rather than joining this list quietly.
--
-- What it costs when one lands. A NaN is absorbing under every aggregate the
-- app runs and outranks every real value in a descending sort:
--
--   * `gym_sets.weight_kg` feeds `refresh_gym_workout_totals`, so one NaN set
--     makes the DERIVED CACHE `gym_workouts.volume_kg` NaN for that workout —
--     a wrong number shown with total confidence, and the `/gym` list reads
--     the column rather than recomputing. `gym_workout_summaries.is_pr`
--     compares against `max(weight_kg)`, which NaN wins.
--   * the nine `food_log` nutrient columns are summed for the day and then
--     compared against a ceiling. `NaN >= ceiling` is true, so the diary
--     reports the runner blew past their sodium limit off a value nothing
--     measured, and `remaining` is NaN.
--   * `recipes.servings` is a DIVISOR (`sumRecipe` divides the ingredient
--     total by it), and `recipe_ingredients.quantity` a multiplier.
--   * `challenges.goal_value` NaN makes `recompute_challenge_completion`'s
--     `value >= goal` false forever: the challenge becomes unwinnable and
--     nothing on either client says so. That constraint's own migration
--     (20270615_001) exists to stop precisely this — an unwinnable goal — and
--     its client half already refuses a non-finite value (`Number.isFinite` in
--     `checkChallengeGoal`), so the two halves disagreed about a row that can
--     exist.
--   * `segments.end_distance_m` carries no bound of its own; the pair
--     constraints `end > start` and `end - start >= 100` are BOTH satisfied by
--     a NaN end, so it gets its own bound here rather than a NaN term.
--
-- Infinity is a narrower problem and is named only where the column can hold
-- one. A `numeric(p, s)` rejects an infinite value at the type with a 22003
-- field overflow before any CHECK is consulted, so a `<> 'Infinity'` term on a
-- scaled column would be dead. The five that can hold one are the bare
-- `numeric` and `double precision` columns: `event_results.distance_m`,
-- `global_segment_efforts.time_seconds`, `global_segments.distance_m`,
-- `segment_efforts.time_seconds`, `segments.start_distance_m` /
-- `end_distance_m`, and `challenges.goal_value`. `-Infinity` needs no term:
-- every bound here has a lower edge that already excludes it.
--
-- Online-safety (docs/backend/migration_locks.md). Each table's constraints
-- are dropped and re-added in ONE `alter table`, so a table pays a single
-- brief ACCESS EXCLUSIVE for all of its columns rather than one per column,
-- and every add is `NOT VALID` — a metadata flip, no scan. The validations are
-- separate statements under SHARE UPDATE EXCLUSIVE, where readers and writers
-- proceed. `segment_efforts` is in the guard's high-volume set and is the
-- reason the two-step is not optional here.
--
-- No repair pass, matching 20260621_001 and 20270615_001: a NaN in one of
-- these columns has no honest replacement (0 is a measurement, NULL is not
-- available on the NOT NULL ones), so an offending row is investigated rather
-- than rewritten. Run these before applying to a populated instance — every
-- one must return 0, or the matching VALIDATE fails:
--
--   select count(*) from food_log
--    where calories = 'NaN' or carbs_g = 'NaN' or cholesterol_mg = 'NaN'
--       or fat_g = 'NaN' or fiber_g = 'NaN' or protein_g = 'NaN'
--       or saturated_fat_g = 'NaN' or sodium_mg = 'NaN' or sugar_g = 'NaN';
--   select count(*) from gym_sets where weight_kg = 'NaN';
--   select count(*) from recipes where servings = 'NaN';
--   select count(*) from recipe_ingredients
--    where quantity = 'NaN' or calories = 'NaN' or carbs_g = 'NaN'
--       or fat_g = 'NaN' or protein_g = 'NaN';
--   select count(*) from meal_template_items
--    where calories = 'NaN' or carbs_g = 'NaN' or fat_g = 'NaN' or protein_g = 'NaN';
--   select count(*) from gym_routine_sets
--    where target_distance_m = 'NaN' or target_weight_kg = 'NaN';
--   select count(*) from event_results
--    where distance_m = 'NaN' or distance_m = 'Infinity';
--   select count(*) from segment_efforts
--    where time_seconds = 'NaN' or time_seconds = 'Infinity';
--   select count(*) from global_segment_efforts
--    where time_seconds = 'NaN' or time_seconds = 'Infinity';
--   select count(*) from global_segments
--    where distance_m = 'NaN' or distance_m = 'Infinity';
--   select count(*) from segments
--    where start_distance_m in ('NaN', 'Infinity')
--       or end_distance_m in ('NaN', 'Infinity');
--   select count(*) from challenges
--    where goal_value = 'NaN' or goal_value = 'Infinity';
--
-- No column type, nullability or default moves, so neither row-type generator
-- has anything to regenerate.

alter table event_results
  drop constraint event_results_distance_m_check,
  add constraint event_results_distance_m_check
    check (distance_m >= 0 and distance_m <> 'NaN'::float8 and distance_m <> 'Infinity'::float8) not valid;

alter table event_results validate constraint event_results_distance_m_check;

alter table food_log
  drop constraint food_log_calories_check,
  add constraint food_log_calories_check
    check (calories is null or (calories >= 0 and calories <> 'NaN'::numeric)) not valid,
  drop constraint food_log_carbs_g_check,
  add constraint food_log_carbs_g_check
    check (carbs_g is null or (carbs_g >= 0 and carbs_g <> 'NaN'::numeric)) not valid,
  drop constraint food_log_cholesterol_mg_check,
  add constraint food_log_cholesterol_mg_check
    check (cholesterol_mg is null or (cholesterol_mg >= 0 and cholesterol_mg <> 'NaN'::numeric)) not valid,
  drop constraint food_log_fat_g_check,
  add constraint food_log_fat_g_check
    check (fat_g is null or (fat_g >= 0 and fat_g <> 'NaN'::numeric)) not valid,
  drop constraint food_log_fiber_g_check,
  add constraint food_log_fiber_g_check
    check (fiber_g is null or (fiber_g >= 0 and fiber_g <> 'NaN'::numeric)) not valid,
  drop constraint food_log_protein_g_check,
  add constraint food_log_protein_g_check
    check (protein_g is null or (protein_g >= 0 and protein_g <> 'NaN'::numeric)) not valid,
  drop constraint food_log_saturated_fat_g_check,
  add constraint food_log_saturated_fat_g_check
    check (saturated_fat_g is null or (saturated_fat_g >= 0 and saturated_fat_g <> 'NaN'::numeric)) not valid,
  drop constraint food_log_sodium_mg_check,
  add constraint food_log_sodium_mg_check
    check (sodium_mg is null or (sodium_mg >= 0 and sodium_mg <> 'NaN'::numeric)) not valid,
  drop constraint food_log_sugar_g_check,
  add constraint food_log_sugar_g_check
    check (sugar_g is null or (sugar_g >= 0 and sugar_g <> 'NaN'::numeric)) not valid;

alter table food_log validate constraint food_log_calories_check;
alter table food_log validate constraint food_log_carbs_g_check;
alter table food_log validate constraint food_log_cholesterol_mg_check;
alter table food_log validate constraint food_log_fat_g_check;
alter table food_log validate constraint food_log_fiber_g_check;
alter table food_log validate constraint food_log_protein_g_check;
alter table food_log validate constraint food_log_saturated_fat_g_check;
alter table food_log validate constraint food_log_sodium_mg_check;
alter table food_log validate constraint food_log_sugar_g_check;

alter table global_segment_efforts
  drop constraint global_segment_efforts_time_seconds_check,
  add constraint global_segment_efforts_time_seconds_check
    check (time_seconds > 0 and time_seconds <> 'NaN'::numeric and time_seconds <> 'Infinity'::numeric) not valid;

alter table global_segment_efforts validate constraint global_segment_efforts_time_seconds_check;

alter table global_segments
  drop constraint global_segments_distance_m_check,
  add constraint global_segments_distance_m_check
    check (distance_m >= 100 and distance_m <> 'NaN'::numeric and distance_m <> 'Infinity'::numeric) not valid;

alter table global_segments validate constraint global_segments_distance_m_check;

alter table gym_routine_sets
  drop constraint gym_routine_sets_target_distance_m_check,
  add constraint gym_routine_sets_target_distance_m_check
    check (target_distance_m is null or (target_distance_m >= 0 and target_distance_m <> 'NaN'::numeric)) not valid,
  drop constraint gym_routine_sets_target_weight_kg_check,
  add constraint gym_routine_sets_target_weight_kg_check
    check (target_weight_kg is null or (target_weight_kg >= 0 and target_weight_kg <> 'NaN'::numeric)) not valid;

alter table gym_routine_sets validate constraint gym_routine_sets_target_distance_m_check;
alter table gym_routine_sets validate constraint gym_routine_sets_target_weight_kg_check;

alter table gym_sets
  drop constraint gym_sets_weight_kg_check,
  add constraint gym_sets_weight_kg_check
    check (weight_kg is null or (weight_kg >= 0 and weight_kg <> 'NaN'::numeric)) not valid;

alter table gym_sets validate constraint gym_sets_weight_kg_check;

alter table meal_template_items
  drop constraint meal_template_items_calories_check,
  add constraint meal_template_items_calories_check
    check (calories is null or (calories >= 0 and calories <> 'NaN'::numeric)) not valid,
  drop constraint meal_template_items_carbs_g_check,
  add constraint meal_template_items_carbs_g_check
    check (carbs_g is null or (carbs_g >= 0 and carbs_g <> 'NaN'::numeric)) not valid,
  drop constraint meal_template_items_fat_g_check,
  add constraint meal_template_items_fat_g_check
    check (fat_g is null or (fat_g >= 0 and fat_g <> 'NaN'::numeric)) not valid,
  drop constraint meal_template_items_protein_g_check,
  add constraint meal_template_items_protein_g_check
    check (protein_g is null or (protein_g >= 0 and protein_g <> 'NaN'::numeric)) not valid;

alter table meal_template_items validate constraint meal_template_items_calories_check;
alter table meal_template_items validate constraint meal_template_items_carbs_g_check;
alter table meal_template_items validate constraint meal_template_items_fat_g_check;
alter table meal_template_items validate constraint meal_template_items_protein_g_check;

alter table recipe_ingredients
  drop constraint recipe_ingredients_calories_check,
  add constraint recipe_ingredients_calories_check
    check (calories is null or (calories >= 0 and calories <> 'NaN'::numeric)) not valid,
  drop constraint recipe_ingredients_carbs_g_check,
  add constraint recipe_ingredients_carbs_g_check
    check (carbs_g is null or (carbs_g >= 0 and carbs_g <> 'NaN'::numeric)) not valid,
  drop constraint recipe_ingredients_fat_g_check,
  add constraint recipe_ingredients_fat_g_check
    check (fat_g is null or (fat_g >= 0 and fat_g <> 'NaN'::numeric)) not valid,
  drop constraint recipe_ingredients_protein_g_check,
  add constraint recipe_ingredients_protein_g_check
    check (protein_g is null or (protein_g >= 0 and protein_g <> 'NaN'::numeric)) not valid,
  drop constraint recipe_ingredients_quantity_check,
  add constraint recipe_ingredients_quantity_check
    check (quantity >= 0 and quantity <> 'NaN'::numeric) not valid;

alter table recipe_ingredients validate constraint recipe_ingredients_calories_check;
alter table recipe_ingredients validate constraint recipe_ingredients_carbs_g_check;
alter table recipe_ingredients validate constraint recipe_ingredients_fat_g_check;
alter table recipe_ingredients validate constraint recipe_ingredients_protein_g_check;
alter table recipe_ingredients validate constraint recipe_ingredients_quantity_check;

alter table recipes
  drop constraint recipes_servings_check,
  add constraint recipes_servings_check
    check (servings >= 1 and servings <> 'NaN'::numeric) not valid;

alter table recipes validate constraint recipes_servings_check;

alter table segment_efforts
  drop constraint segment_efforts_time_seconds_check,
  add constraint segment_efforts_time_seconds_check
    check (time_seconds > 0 and time_seconds <> 'NaN'::numeric and time_seconds <> 'Infinity'::numeric) not valid;

alter table segment_efforts validate constraint segment_efforts_time_seconds_check;

alter table segments
  drop constraint segments_start_distance_m_check,
  add constraint segments_start_distance_m_check
    check (start_distance_m >= 0 and start_distance_m <> 'NaN'::numeric and start_distance_m <> 'Infinity'::numeric) not valid;

alter table segments validate constraint segments_start_distance_m_check;

-- segments.end_distance_m had no bound of its own. `end > start` and
-- `end - start >= 100` are both TRUE for a NaN end against any real start, so
-- the pair constraints did not stand in for one.
alter table segments
  add constraint segments_end_distance_m_check
    check (
      end_distance_m >= 0
      and end_distance_m <> 'NaN'::numeric
      and end_distance_m <> 'Infinity'::numeric
    ) not valid;

alter table segments validate constraint segments_end_distance_m_check;

-- challenges_goal_ck (20270615_001) is the multi-column case: the whole point
-- of the constraint is that a stored goal is one a participant can actually
-- reach, and `NaN > 0` let through a goal `value >= goal` can never satisfy.
alter table challenges
  drop constraint challenges_goal_ck,
  add constraint challenges_goal_ck
    check (
      goal_value is null
      or (
        goal_value > 0
        and goal_value <> 'NaN'::numeric
        and goal_value <> 'Infinity'::numeric
        and (
          metric <> 'streak_days'
          or goal_value <= floor(extract(epoch from (ends_at - starts_at)) / 86400) + 1
        )
      )
    ) not valid;

alter table challenges validate constraint challenges_goal_ck;

comment on constraint challenges_goal_ck on challenges is
  'A stored goal is positive, finite, and — for streak_days — no larger than '
  'the distinct UTC dates the window can touch. The finiteness terms are '
  'load-bearing: NaN > 0 is true, and a NaN goal makes value >= goal false '
  'forever, so the challenge is unwinnable and silent about it. Mirrored '
  'client-side by checkChallengeGoal / maxStreakDaysInWindow on both platforms.';
