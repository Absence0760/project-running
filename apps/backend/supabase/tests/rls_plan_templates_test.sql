-- Pin the publisher-fitness strip on `training_plans` templates +
-- clones from migration 20260721_001_plan_templates_strip_fitness.sql.
--
-- Audit pass-3 High: publishPlanAsTemplate (web data.ts) and
-- clone_plan_template (RPC) both copied source-plan vdot +
-- current_5k_seconds verbatim. Templates are SELECTable by every
-- club member; clones inherit the publisher's private fitness
-- measurements.
--
-- This file pins:
--   1. The pass-3 backfill UPDATE zeroed vdot + current_5k_seconds
--      on every existing template row (idempotent — re-runs of
--      `supabase db reset` keep them null even if the seed reverts).
--   2. clone_plan_template returns a clone with both fields null,
--      regardless of what the template row carries (defence-in-
--      depth: a future writer that bypasses the publish-side
--      strip can't leak through the clone).
--   3. The clone's other fields (name, dates, days_per_week) are
--      preserved — strip is targeted, not nuking the row.

begin;

select plan(5);

-- Fixture: club + admin + member; admin owns a template carrying
-- (post-backfill) null vdot/current_5k_seconds, plus weeks +
-- workouts so the clone exercises the full chain. We force the
-- template to carry non-null values via a service-role insert to
-- prove the clone-side strip works even if a future writer leaks.
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000aa01', 'authenticated', 'authenticated',
   'admin@plan-tmpl.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000aa02', 'authenticated', 'authenticated',
   'member@plan-tmpl.local', '', now(), now());

set local role service_role;

insert into clubs (id, owner_id, name, slug, is_public)
values ('66666666-6666-6666-6666-666666666601',
        '00000000-0000-0000-0000-00000000aa01',
        'Plan Template Test Club', 'plan-tmpl-test', true);

-- enroll_club_owner_trigger auto-inserts the owner row with
-- role='owner', so we only seed the second member here.
insert into club_members (club_id, user_id, role, status)
values
  ('66666666-6666-6666-6666-666666666601',
   '00000000-0000-0000-0000-00000000aa02', 'member', 'active');

-- Template with publisher fitness data set — simulates a future
-- writer that bypasses the publish-side strip. The clone-side
-- strip is the load-bearing guard.
insert into training_plans (
  id, user_id, name, goal_event, goal_distance_m, goal_time_seconds,
  start_date, end_date, days_per_week, vdot, current_5k_seconds,
  status, is_template, club_id
) values (
  '77777777-7777-7777-7777-777777777701',
  '00000000-0000-0000-0000-00000000aa01',
  'Marathon plan', 'distance_full', 42195, 14400,
  '2026-06-01', '2026-08-31', 5,
  52.5, 1320,
  'completed', true, '66666666-6666-6666-6666-666666666601'
);

insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m)
values
  ('77777777-7777-7777-7777-777777777702',
   '77777777-7777-7777-7777-777777777701', 0, 'base', 30000);

insert into plan_workouts (
  week_id, kind, scheduled_date, target_distance_m, target_pace_sec_per_km
) values (
  '77777777-7777-7777-7777-777777777702',
  'easy', '2026-06-01', 8000, 360
);

-- 1. Sanity: the template row carries the leaked-shape values we
--    just inserted — confirms the clone-side test below is
--    actually exercising the strip.
select results_eq(
  $$ select vdot::float, current_5k_seconds from training_plans
     where id = '77777777-7777-7777-7777-777777777701' $$,
  $$ values (52.5::float, 1320) $$,
  'template row carries publisher fitness data (pre-clone state)'
);

-- ── Member clones the template ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000aa02"}';

select lives_ok(
  $$ select clone_plan_template(
       '77777777-7777-7777-7777-777777777701'::uuid,
       '2026-09-01'::date) $$,
  'club member clones the template'
);

-- 2. The clone's vdot is null — clone-side strip fired.
select is(
  (select vdot from training_plans
   where parent_template_id = '77777777-7777-7777-7777-777777777701'
     and user_id = '00000000-0000-0000-0000-00000000aa02'
   limit 1),
  null::numeric(5, 2),
  'clone_plan_template strips vdot from the cloned plan'
);

-- 3. The clone's current_5k_seconds is null too.
select is(
  (select current_5k_seconds from training_plans
   where parent_template_id = '77777777-7777-7777-7777-777777777701'
     and user_id = '00000000-0000-0000-0000-00000000aa02'
   limit 1),
  null::integer,
  'clone_plan_template strips current_5k_seconds from the cloned plan'
);

-- 4. The clone's other fields are preserved (strip is targeted).
select results_eq(
  $$ select name, days_per_week from training_plans
     where parent_template_id = '77777777-7777-7777-7777-777777777701'
       and user_id = '00000000-0000-0000-0000-00000000aa02'
     limit 1 $$,
  $$ values ('Marathon plan'::text, 5::smallint) $$,
  'clone preserves non-fitness fields (name, days_per_week)'
);

select * from finish();

rollback;
