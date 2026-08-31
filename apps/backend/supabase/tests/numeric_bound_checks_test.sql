-- The numeric CHECK bounds decisions § 792 measured, pinned at their edges.
--
-- § 792 is about the four inputs that could hand a runner a raw postgres
-- error: a client that does not mirror a server bound turns a typo into a
-- 23514 the UI has no sentence for. `check_shared_constants.mjs` keeps the
-- client copies in step with these numbers by reading the migrations; nothing
-- reads the DATABASE. So a migration that widened, narrowed or dropped one of
-- these constraints would leave the guard green — it compares two declarations
-- of the bound, not the bound and its effect — while the column silently
-- accepted a weight of 900 kg or refused a legitimate 500.
--
-- Every bound is asserted at BOTH edges: the extreme value the column must
-- accept, and the smallest representable step past it, which is what the
-- column's own scale allows (`numeric(5,2)` cannot express 500.001, so the
-- step past 500 is 500.01). An at-cap acceptance is the half that catches a
-- bound tightened by accident; a past-cap refusal is the half that catches one
-- widened or dropped.
--
-- `free_text_caps_test` and `content_length_caps_test` cover the length caps,
-- and `body_metrics_rls_test` covers weight at 0 and 900 — far outside the
-- range, so neither edge was ever measured. These are the numeric siblings.
--
-- Written under the service role: the subject is the constraint, not the
-- policy, and every one of these tables refuses the client verb for its own
-- separate reason.

begin;
select plan(32);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('b0000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'bounds@num.local', '', now(), now());

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

insert into user_profiles (id, display_name, preferred_unit)
values ('b0000000-0000-0000-0000-000000000001', 'Bounds Runner', 'km');

-- ── body_metrics.weight_kg: > 0 and <= 500, numeric(5,2) ────────────────────
select lives_ok(
  $$ insert into body_metrics (user_id, weight_kg)
     values ('b0000000-0000-0000-0000-000000000001', 500) $$,
  'a 500 kg weight is accepted at the cap'
);
select throws_ok(
  $$ insert into body_metrics (user_id, weight_kg)
     values ('b0000000-0000-0000-0000-000000000001', 500.01) $$,
  '23514', null,
  'one hundredth past the weight cap is rejected'
);
select lives_ok(
  $$ insert into body_metrics (user_id, weight_kg)
     values ('b0000000-0000-0000-0000-000000000001', 0.01) $$,
  'the smallest representable positive weight is accepted'
);
select throws_ok(
  $$ insert into body_metrics (user_id, weight_kg)
     values ('b0000000-0000-0000-0000-000000000001', 0) $$,
  '23514', null,
  'a zero weight is rejected — the floor is strict'
);

-- ── user_profiles.height_cm: > 0 and <= 300, numeric(5,1) ───────────────────
select lives_ok(
  $$ update user_profiles set height_cm = 300
      where id = 'b0000000-0000-0000-0000-000000000001' $$,
  'a 300 cm height is accepted at the cap'
);
select throws_ok(
  $$ update user_profiles set height_cm = 300.1
      where id = 'b0000000-0000-0000-0000-000000000001' $$,
  '23514', null,
  'one tenth past the height cap is rejected'
);
select throws_ok(
  $$ update user_profiles set height_cm = 0
      where id = 'b0000000-0000-0000-0000-000000000001' $$,
  '23514', null,
  'a zero height is rejected — the floor is strict'
);
select lives_ok(
  $$ update user_profiles set height_cm = null
      where id = 'b0000000-0000-0000-0000-000000000001' $$,
  'a null height is still allowed — the column is optional'
);

-- ── gym_routine_sets: the prescription bounds ───────────────────────────────
insert into gym_routines (id, author_id, title)
values ('b0000000-0000-0000-0000-00000000a001', 'b0000000-0000-0000-0000-000000000001',
        'Bounds Routine');
insert into gym_routine_exercises (id, routine_id, exercise_name, exercise_key, position)
values ('b0000000-0000-0000-0000-00000000a002', 'b0000000-0000-0000-0000-00000000a001',
        'Bench Press', public.normalise_exercise_name('Bench Press'), 0);

select lives_ok(
  $$ insert into gym_routine_sets (routine_exercise_id, set_index, target_percent_1rm)
     values ('b0000000-0000-0000-0000-00000000a002', 0, 200) $$,
  '200 percent of 1RM is accepted at the cap'
);
select throws_ok(
  $$ insert into gym_routine_sets (routine_exercise_id, set_index, target_percent_1rm)
     values ('b0000000-0000-0000-0000-00000000a002', 1, 200.01) $$,
  '23514', null,
  'one hundredth past the percent-of-1RM cap is rejected'
);
select throws_ok(
  $$ insert into gym_routine_sets (routine_exercise_id, set_index, target_percent_1rm)
     values ('b0000000-0000-0000-0000-00000000a002', 2, 0) $$,
  '23514', null,
  'a zero percent of 1RM is rejected — the floor is strict'
);
select lives_ok(
  $$ insert into gym_routine_sets (routine_exercise_id, set_index, target_percent_1rm)
     values ('b0000000-0000-0000-0000-00000000a002', 3, null) $$,
  'a set with no percent-of-1RM target is still allowed'
);

select lives_ok(
  $$ insert into gym_routine_sets (routine_exercise_id, set_index, target_rpe)
     values ('b0000000-0000-0000-0000-00000000a002', 4, 10) $$,
  'an RPE of 10 is accepted at the cap'
);
select throws_ok(
  $$ insert into gym_routine_sets (routine_exercise_id, set_index, target_rpe)
     values ('b0000000-0000-0000-0000-00000000a002', 5, 10.1) $$,
  '23514', null,
  'one tenth past the RPE cap is rejected'
);
select lives_ok(
  $$ insert into gym_routine_sets (routine_exercise_id, set_index, target_rpe)
     values ('b0000000-0000-0000-0000-00000000a002', 6, 0) $$,
  'an RPE of 0 is accepted — this floor is inclusive, unlike the 1RM one'
);
select throws_ok(
  $$ insert into gym_routine_sets (routine_exercise_id, set_index, target_rpe)
     values ('b0000000-0000-0000-0000-00000000a002', 7, -0.1) $$,
  '23514', null,
  'a negative RPE is rejected'
);

select lives_ok(
  $$ insert into gym_routine_sets (routine_exercise_id, set_index, rest_s)
     values ('b0000000-0000-0000-0000-00000000a002', 8, 3600) $$,
  'an hour of rest is accepted at the cap'
);
select throws_ok(
  $$ insert into gym_routine_sets (routine_exercise_id, set_index, rest_s)
     values ('b0000000-0000-0000-0000-00000000a002', 9, 3601) $$,
  '23514', null,
  'one second past the rest cap is rejected'
);
select throws_ok(
  $$ insert into gym_routine_sets (routine_exercise_id, set_index, rest_s)
     values ('b0000000-0000-0000-0000-00000000a002', 10, -1) $$,
  '23514', null,
  'a negative rest is rejected'
);

-- ── recipes.servings: >= 1, numeric(5,1) ────────────────────────────────────
select lives_ok(
  $$ insert into recipes (user_id, name, servings)
     values ('b0000000-0000-0000-0000-000000000001', 'One serving', 1) $$,
  'a single serving is accepted at the floor'
);
select throws_ok(
  $$ insert into recipes (user_id, name, servings)
     values ('b0000000-0000-0000-0000-000000000001', 'Nine tenths', 0.9) $$,
  '23514', null,
  'a fraction of a serving is rejected — the divisor cannot round to zero'
);
select throws_ok(
  $$ insert into recipes (user_id, name, servings)
     values ('b0000000-0000-0000-0000-000000000001', 'No servings', 0) $$,
  '23514', null,
  'zero servings is rejected — the per-serving macros would divide by it'
);

-- ── training_plans.days_per_week: 3..7 ──────────────────────────────────────
-- `training_plans_one_active` is a partial unique index on (user_id) where
-- status = 'active', so every plan here is filed completed: the subject is the
-- bound, and a second active plan would fail with a 23505 that says nothing
-- about it.
select lives_ok(
  $$ insert into training_plans (user_id, name, goal_event, goal_distance_m,
                                 start_date, end_date, days_per_week, status)
     values ('b0000000-0000-0000-0000-000000000001', 'Three days', 'distance_5k', 5000,
             '2026-01-04', '2026-03-01', 3, 'completed') $$,
  'three days a week is accepted at the floor'
);
select lives_ok(
  $$ insert into training_plans (user_id, name, goal_event, goal_distance_m,
                                 start_date, end_date, days_per_week, status)
     values ('b0000000-0000-0000-0000-000000000001', 'Seven days', 'distance_5k', 5000,
             '2026-01-04', '2026-03-01', 7, 'completed') $$,
  'seven days a week is accepted at the cap'
);
select throws_ok(
  $$ insert into training_plans (user_id, name, goal_event, goal_distance_m,
                                 start_date, end_date, days_per_week, status)
     values ('b0000000-0000-0000-0000-000000000001', 'Two days', 'distance_5k', 5000,
             '2026-01-04', '2026-03-01', 2, 'completed') $$,
  '23514', null,
  'two days a week is rejected — the generator has no plan shape for it'
);
select throws_ok(
  $$ insert into training_plans (user_id, name, goal_event, goal_distance_m,
                                 start_date, end_date, days_per_week, status)
     values ('b0000000-0000-0000-0000-000000000001', 'Eight days', 'distance_5k', 5000,
             '2026-01-04', '2026-03-01', 8, 'completed') $$,
  '23514', null,
  'eight days a week is rejected'
);
select throws_ok(
  $$ insert into training_plans (user_id, name, goal_event, goal_distance_m,
                                 start_date, end_date, days_per_week, status)
     values ('b0000000-0000-0000-0000-000000000001', 'Backwards', 'distance_5k', 5000,
             '2026-03-01', '2026-01-04', 4, 'completed') $$,
  '23514', null,
  'a plan that ends before it starts is rejected'
);

-- ── checkpoint_crossings.body_weight_kg: 20..400, the Art 9 weigh-in ────────
insert into clubs (id, owner_id, name, slug, is_public)
values ('b0000000-0000-0000-0000-00000000b001', 'b0000000-0000-0000-0000-000000000001',
        'Bounds Club', 'bounds-club', true);
insert into events (id, club_id, title, starts_at, author_id)
values ('b0000000-0000-0000-0000-00000000b002', 'b0000000-0000-0000-0000-00000000b001',
        'Bounds 50k', '2026-06-06 06:00+00', 'b0000000-0000-0000-0000-000000000001');
insert into event_checkpoints (id, event_id, name, ordinal, requires_weigh_in, created_by)
values ('b0000000-0000-0000-0000-00000000b003', 'b0000000-0000-0000-0000-00000000b002',
        'Scale', 1, true, 'b0000000-0000-0000-0000-000000000001');

select lives_ok(
  $$ insert into checkpoint_crossings (event_id, checkpoint_id, instance_start,
                                       bib, body_weight_kg)
     values ('b0000000-0000-0000-0000-00000000b002', 'b0000000-0000-0000-0000-00000000b003',
             '2026-06-06 06:00+00', 'lo', 20) $$,
  'a 20 kg weigh-in is accepted at the floor'
);
select lives_ok(
  $$ insert into checkpoint_crossings (event_id, checkpoint_id, instance_start,
                                       bib, body_weight_kg)
     values ('b0000000-0000-0000-0000-00000000b002', 'b0000000-0000-0000-0000-00000000b003',
             '2026-06-06 06:00+00', 'hi', 400) $$,
  'a 400 kg weigh-in is accepted at the cap'
);
select throws_ok(
  $$ insert into checkpoint_crossings (event_id, checkpoint_id, instance_start,
                                       bib, body_weight_kg)
     values ('b0000000-0000-0000-0000-00000000b002', 'b0000000-0000-0000-0000-00000000b003',
             '2026-06-06 06:00+00', 'under', 19.99) $$,
  '23514', null,
  'one hundredth under the weigh-in floor is rejected'
);
select throws_ok(
  $$ insert into checkpoint_crossings (event_id, checkpoint_id, instance_start,
                                       bib, body_weight_kg)
     values ('b0000000-0000-0000-0000-00000000b002', 'b0000000-0000-0000-0000-00000000b003',
             '2026-06-06 06:00+00', 'over', 400.01) $$,
  '23514', null,
  'one hundredth over the weigh-in cap is rejected'
);
select lives_ok(
  $$ insert into checkpoint_crossings (event_id, checkpoint_id, instance_start,
                                       bib, body_weight_kg)
     values ('b0000000-0000-0000-0000-00000000b002', 'b0000000-0000-0000-0000-00000000b003',
             '2026-06-06 06:00+00', 'none', null) $$,
  'a crossing with no weigh-in is still allowed — the column is optional'
);

select * from finish();
rollback;
