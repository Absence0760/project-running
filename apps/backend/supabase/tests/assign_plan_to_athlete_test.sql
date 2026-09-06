-- pgtap suite for assign_plan_to_athlete (20270106_001).
--
-- An active coach can deep-clone one of their own plans into an ATHLETE-OWNED
-- active plan. A stranger / ended link cannot; the source must be readable by
-- the coach; the athlete must not already have an active plan; nobody can
-- assign to themselves.
--
-- And the copy carries the PLAN, not the coach. The source here is the coach's
-- own personal plan, which -- unlike a template -- can hold `vdot`,
-- `current_5k_seconds` and plan-level `notes`, the three columns 20270508_001
-- classified owner-only. 20270711000002 nulls them on the row the athlete owns.
-- Asserted at the assigned row rather than at the source, which is the opposite
-- of `plan_clone_pace_columns_test`'s call for the template paths and for the
-- same reason: there the trigger makes the source incapable of holding the
-- values, so the clone's own `null, null` has nothing to copy and a mutation
-- survives; here the source DOES hold them, so the assigned row is the only
-- place the copy can be observed.

begin;

select plan(11);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000000c1', 'authenticated', 'authenticated',
   'coach@assign.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000000a2', 'authenticated', 'authenticated',
   'athlete-clean@assign.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000000a6', 'authenticated', 'authenticated',
   'athlete-link2@assign.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000000a4', 'authenticated', 'authenticated',
   'athlete-hasplan@assign.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000000d3', 'authenticated', 'authenticated',
   'stranger@assign.local', '', now(), now());

-- Active links C1→A2, C1→A6, C1→A4 (seeded as superuser, before any set role).
insert into coach_athletes (coach_id, athlete_id, status, invite_token) values
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000a2', 'active', 'tok-assign-a2'),
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000a6', 'active', 'tok-assign-a6'),
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000a4', 'active', 'tok-assign-a4');

-- Coach C1 owns a source plan with one week + one workout.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000000c1"}';
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date,
   vdot, current_5k_seconds, notes, rules)
values ('aaaaaaaa-0000-0000-0000-00000000dd01',
   '00000000-0000-0000-0000-0000000000c1', 'Coach Marathon Block', 'distance_full', 42195,
   current_date, current_date + 84,
   -- The coach's own fitness and their own plan-level free text. A template
   -- could not hold these (the strip trigger); a personal plan can, which is
   -- what made this path the outlier.
   58.4, 1020, 'left achilles still grumbling on hills', '["80% easy"]'::jsonb);
insert into plan_weeks (id, plan_id, week_index, phase)
values ('aaaaaaaa-0000-0000-0000-00000000ee01',
   'aaaaaaaa-0000-0000-0000-00000000dd01', 0, 'base');
insert into plan_workouts (id, week_id, scheduled_date, kind, target_pace_sec_per_km, notes)
values ('aaaaaaaa-0000-0000-0000-00000000ff01',
   'aaaaaaaa-0000-0000-0000-00000000ee01', current_date, 'easy', 360, 'easy 8k');

-- Stranger D3 owns a private plan C1 must not be able to launder.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000000d3"}';
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date)
values ('aaaaaaaa-0000-0000-0000-00000000dd03',
   '00000000-0000-0000-0000-0000000000d3', 'Private Plan', 'distance_10k', 10000,
   current_date, current_date + 56);

-- Athlete A4 already has their own active plan (the conflict case).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000000a4"}';
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date)
values ('aaaaaaaa-0000-0000-0000-00000000dd04',
   '00000000-0000-0000-0000-0000000000a4', 'Self-made plan', 'distance_5k', 5000,
   current_date, current_date + 42);

-- ── 1. Active coach assigns the source plan to A2 (happy path). ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000000c1"}';
select lives_ok(
  $$ select assign_plan_to_athlete(
       'aaaaaaaa-0000-0000-0000-00000000dd01',
       '00000000-0000-0000-0000-0000000000a2',
       current_date) $$,
  'active coach can assign a plan to a linked athlete'
);

-- ── 2. The assigned plan is athlete-owned, active, with coach provenance. ──
set local role postgres;
select is(
  (select count(*)::int from training_plans
     where user_id = '00000000-0000-0000-0000-0000000000a2'
       and status = 'active'
       and is_template = false
       and assigned_by_coach_id = '00000000-0000-0000-0000-0000000000c1'
       and parent_template_id = 'aaaaaaaa-0000-0000-0000-00000000dd01'),
  1,
  'assigned plan is athlete-owned + active + stamped with coach provenance'
);

-- ── 3. The deep-clone copied the week + workout into the athlete's plan. ──
select is(
  (select count(*)::int
     from plan_workouts w
     join plan_weeks pw on pw.id = w.week_id
     join training_plans p on p.id = pw.plan_id
    where p.user_id = '00000000-0000-0000-0000-0000000000a2'
      and p.assigned_by_coach_id = '00000000-0000-0000-0000-0000000000c1'),
  1,
  'assigned plan deep-cloned the source week + workout'
);
-- ── 4. The coach's own fitness and free text do not ride along. ──
select is(
  (select coalesce(vdot::text, 'null') || '/' ||
          coalesce(current_5k_seconds::text, 'null') || '/' ||
          coalesce(notes, 'null')
     from training_plans
    where user_id = '00000000-0000-0000-0000-0000000000a2'
      and assigned_by_coach_id = '00000000-0000-0000-0000-0000000000c1'),
  'null/null/null',
  'the assigned plan carries none of the coach''s owner-private columns'
);

-- ── 5. Stripping the COPY is not editing the coach's own plan. ──
select is(
  (select coalesce(vdot::text, 'null') || '/' ||
          coalesce(current_5k_seconds::text, 'null') || '/' ||
          coalesce(notes, 'null')
     from training_plans where id = 'aaaaaaaa-0000-0000-0000-00000000dd01'),
  '58.40/1020/left achilles still grumbling on hills',
  'the coach''s source plan keeps its own fitness and notes'
);

-- ── 6. `rules` is the sanctioned prose channel and still propagates. ──
--    Without this, nulling `notes` reads as "strip the prose", and the next
--    edit takes `rules` with it -- which 20270710000003 added on purpose.
select is(
  (select rules from training_plans
    where user_id = '00000000-0000-0000-0000-0000000000a2'
      and assigned_by_coach_id = '00000000-0000-0000-0000-0000000000c1'),
  '["80% easy"]'::jsonb,
  'the plan-wide rules the coach wrote still reach the athlete'
);
set local role authenticated;

-- ── 7. Coach cannot assign to a user they aren't linked to (stranger). ──
select throws_ok(
  $$ select assign_plan_to_athlete(
       'aaaaaaaa-0000-0000-0000-00000000dd01',
       '00000000-0000-0000-0000-0000000000d3',
       current_date) $$,
  'P0001', NULL,
  'coach cannot assign to an athlete they are not actively linked to'
);

-- ── 8. Nobody can assign a plan to themselves. ──
select throws_ok(
  $$ select assign_plan_to_athlete(
       'aaaaaaaa-0000-0000-0000-00000000dd01',
       '00000000-0000-0000-0000-0000000000c1',
       current_date) $$,
  'P0001', NULL,
  'cannot assign a plan to yourself'
);

-- ── 9. Coach cannot launder a source plan they can't read (D3's private plan). ──
select throws_ok(
  $$ select assign_plan_to_athlete(
       'aaaaaaaa-0000-0000-0000-00000000dd03',
       '00000000-0000-0000-0000-0000000000a6',
       current_date) $$,
  'P0001', NULL,
  'coach cannot assign a source plan they are not authorised to read'
);

-- ── 10. Refuses when the athlete already has an active plan. ──
select throws_ok(
  $$ select assign_plan_to_athlete(
       'aaaaaaaa-0000-0000-0000-00000000dd01',
       '00000000-0000-0000-0000-0000000000a4',
       current_date) $$,
  'P0001', NULL,
  'refuses to assign when the athlete already has an active plan'
);

-- ── 11. Ending the link revokes the ability to assign. ──
set local role postgres;
update coach_athletes set status = 'ended'
 where coach_id = '00000000-0000-0000-0000-0000000000c1'
   and athlete_id = '00000000-0000-0000-0000-0000000000a6';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000000c1"}';
select throws_ok(
  $$ select assign_plan_to_athlete(
       'aaaaaaaa-0000-0000-0000-00000000dd01',
       '00000000-0000-0000-0000-0000000000a6',
       current_date) $$,
  'P0001', NULL,
  'an ended coach link can no longer assign plans'
);

select * from finish();
rollback;
