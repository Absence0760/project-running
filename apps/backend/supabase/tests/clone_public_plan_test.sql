-- Pin the public plan library (migration 20270126_001_public_plan_library):
--   * clone_public_plan clones a public template into a caller-owned plan
--   * authorisation is gated on is_public_template, NOT club membership
--   * a non-public plan is NOT cloneable via clone_public_plan
--   * the publisher's private fitness data (vdot / current_5k_seconds) is
--     stripped from the clone (defence-in-depth, mirrors 20260721_001)
--   * RLS: a stranger (no club tie) can SELECT a public template + its
--     weeks + its workouts (preview), but CANNOT SELECT a private plan
--     they don't own.

begin;

select plan(9);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000ab001', 'authenticated', 'authenticated',
   'author@pub-lib.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000ab002', 'authenticated', 'authenticated',
   'stranger@pub-lib.local', '', now(), now());

set local role service_role;

-- A public template authored by pub01, carrying leaked-shape fitness data
-- (forced via service-role insert) so the clone-side strip is exercised.
insert into training_plans (
  id, user_id, name, goal_event, goal_distance_m, goal_time_seconds,
  start_date, end_date, days_per_week, vdot, current_5k_seconds,
  status, is_template, is_public_template, club_id
) values (
  'aaaaaaaa-0000-0000-0000-0000000ab001',
  '00000000-0000-0000-0000-0000000ab001',
  'Public marathon plan', 'distance_full', 42195, 14400,
  '2026-06-01', '2026-08-31', 5,
  52.5, 1320,
  'completed', true, true, null
);

insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m)
values
  ('aaaaaaaa-0000-0000-0000-0000000abc01',
   'aaaaaaaa-0000-0000-0000-0000000ab001', 0, 'base', 30000);

insert into plan_workouts (
  week_id, kind, scheduled_date, target_distance_m, target_pace_sec_per_km
) values (
  'aaaaaaaa-0000-0000-0000-0000000abc01',
  'easy', '2026-06-01', 8000, 360
);

-- A PRIVATE plan owned by pub01 — the stranger must never see this and
-- must never be able to clone it via clone_public_plan.
insert into training_plans (
  id, user_id, name, goal_event, goal_distance_m,
  start_date, end_date, days_per_week,
  status, is_template, is_public_template, club_id
) values (
  'bbbbbbbb-0000-0000-0000-0000000abd01',
  '00000000-0000-0000-0000-0000000ab001',
  'Private plan', 'distance_full', 42195,
  '2026-06-01', '2026-08-31', 4,
  'active', false, false, null
);

-- ── A stranger (no club tie to anything) acts ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ab002","role":"authenticated"}';

-- 1. RLS: the stranger can SELECT the public template (preview).
select is(
  (select count(*)::int from training_plans
   where id = 'aaaaaaaa-0000-0000-0000-0000000ab001'),
  1,
  'stranger can read a public template row'
);

-- 2. RLS: the stranger can SELECT the public template's weeks.
select is(
  (select count(*)::int from plan_weeks
   where plan_id = 'aaaaaaaa-0000-0000-0000-0000000ab001'),
  1,
  'stranger can read a public template week'
);

-- 3. RLS: the stranger can SELECT the public template's workouts.
select is(
  (select count(*)::int from plan_workouts
   where week_id = 'aaaaaaaa-0000-0000-0000-0000000abc01'),
  1,
  'stranger can read a public template workout'
);

-- 4. RLS: the stranger CANNOT read the author's private plan.
select is(
  (select count(*)::int from training_plans
   where id = 'bbbbbbbb-0000-0000-0000-0000000abd01'),
  0,
  'stranger cannot read a private (non-public) plan'
);

-- 5. Cloning a public template succeeds for a stranger.
select lives_ok(
  $$ select clone_public_plan(
       'aaaaaaaa-0000-0000-0000-0000000ab001'::uuid,
       '2026-09-01'::date) $$,
  'stranger clones a public template'
);

-- 6. The clone's vdot is stripped.
select is(
  (select vdot from training_plans
   where parent_template_id = 'aaaaaaaa-0000-0000-0000-0000000ab001'
     and user_id = '00000000-0000-0000-0000-0000000ab002'
   limit 1),
  null::numeric(5, 2),
  'clone_public_plan strips publisher vdot from the clone'
);

-- 7. The clone's current_5k_seconds is stripped.
select is(
  (select current_5k_seconds from training_plans
   where parent_template_id = 'aaaaaaaa-0000-0000-0000-0000000ab001'
     and user_id = '00000000-0000-0000-0000-0000000ab002'
   limit 1),
  null::integer,
  'clone_public_plan strips publisher current_5k_seconds from the clone'
);

-- 8. The clone is owned by the stranger, active, not itself a template.
select results_eq(
  $$ select user_id, status, is_template, is_public_template
     from training_plans
     where parent_template_id = 'aaaaaaaa-0000-0000-0000-0000000ab001'
       and user_id = '00000000-0000-0000-0000-0000000ab002'
     limit 1 $$,
  $$ values ('00000000-0000-0000-0000-0000000ab002'::uuid,
             'active'::text, false, false) $$,
  'clone is caller-owned, active, and not a template'
);

-- 9. clone_public_plan refuses a NON-public plan (authorisation gate).
select throws_ok(
  $$ select clone_public_plan(
       'bbbbbbbb-0000-0000-0000-0000000abd01'::uuid,
       '2026-09-01'::date) $$,
  'clone_public_plan: public template not found',
  'clone_public_plan refuses a non-public plan'
);

select * from finish();

rollback;
