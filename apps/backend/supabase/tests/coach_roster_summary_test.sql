-- Pins migration 20270206_001 -- coach_roster_summary SECURITY DEFINER
-- aggregation (coach_roster.md).
--
-- The auth boundary is the load-bearing property: the roster returns exactly
-- the coach's ACTIVE-linked athletes, never an ended link, never a stranger,
-- never anything to a non-coach, and raises for an unauthenticated caller.
-- The aggregates (runs_7d / distance_7d_m / plan_completion_pct) match the
-- seeded data, and ending a link mid-test drops the athlete immediately.
begin;
select plan(13);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-0000-0000-0000-0000000000c1', 'authenticated', 'authenticated', 'coach@crs.local', '', now(), now()),
  ('aaaaaaaa-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'athletea@crs.local', '', now(), now()),
  ('aaaaaaaa-0000-0000-0000-0000000000b1', 'authenticated', 'authenticated', 'athleteb@crs.local', '', now(), now()),
  ('aaaaaaaa-0000-0000-0000-0000000000e1', 'authenticated', 'authenticated', 'stranger@crs.local', '', now(), now());

-- Profiles are required (the roster INNER JOINs user_profiles).
insert into user_profiles (id, display_name) values
  ('aaaaaaaa-0000-0000-0000-0000000000a1', 'Athlete A'),
  ('aaaaaaaa-0000-0000-0000-0000000000b1', 'Athlete B'),
  ('aaaaaaaa-0000-0000-0000-0000000000e1', 'Stranger');

-- Links: A is ACTIVE, B is ENDED (revoked). The coach is linked to both rows
-- but only the active one should surface.
insert into coach_athletes (coach_id, athlete_id, status, invite_token, accepted_at) values
  ('aaaaaaaa-0000-0000-0000-0000000000c1', 'aaaaaaaa-0000-0000-0000-0000000000a1', 'active', 'crs-tok-a', now()),
  ('aaaaaaaa-0000-0000-0000-0000000000c1', 'aaaaaaaa-0000-0000-0000-0000000000b1', 'ended', 'crs-tok-b', now());

-- Athlete A: two runs in the last 7d (counted) + one 20-day-old run (in the
-- 28-day chronic window, NOT the 7d acute window) + one is_dnf run in the 7d
-- window that must be EXCLUDED from every aggregate.
insert into runs (id, user_id, started_at, duration_s, distance_m, source, metadata) values
  ('aaaaaaaa-0000-0000-0000-0000000000f1', 'aaaaaaaa-0000-0000-0000-0000000000a1', now() - interval '1 day',  1800, 5000,  'app', '{"activity_type":"run"}'),
  ('aaaaaaaa-0000-0000-0000-0000000000f2', 'aaaaaaaa-0000-0000-0000-0000000000a1', now() - interval '3 days', 2400, 8000,  'app', '{"activity_type":"run"}'),
  ('aaaaaaaa-0000-0000-0000-0000000000f3', 'aaaaaaaa-0000-0000-0000-0000000000a1', now() - interval '20 days', 3600, 12000, 'app', '{"activity_type":"run"}'),
  ('aaaaaaaa-0000-0000-0000-0000000000f4', 'aaaaaaaa-0000-0000-0000-0000000000a1', now() - interval '2 days', 900, 99000, 'app', '{"activity_type":"run","is_dnf":true}');

-- Athlete B (ended link) has runs too -- proves the ended link contributes
-- nothing, not even that it is in the result.
insert into runs (id, user_id, started_at, duration_s, distance_m, source, metadata) values
  ('aaaaaaaa-0000-0000-0000-0000000000d1', 'aaaaaaaa-0000-0000-0000-0000000000b1', now() - interval '1 day', 1800, 5000, 'app', '{"activity_type":"run"}');

-- Athlete A's active plan: one week, two non-rest workouts (one completed via
-- a run, one not) + one rest workout (excluded from the denominator). So
-- completion = 1 done / 1 outstanding-of-2-counted... done=1, total=2 => 50%.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, status)
  values ('aaaaaaaa-0000-0000-0000-0000000000c5', 'aaaaaaaa-0000-0000-0000-0000000000a1',
          'A Plan', 'distance_5k', 5000, current_date, current_date + 28, 'active');
insert into plan_weeks (id, plan_id, week_index, phase)
  values ('aaaaaaaa-0000-0000-0000-0000000000c6', 'aaaaaaaa-0000-0000-0000-0000000000c5', 0, 'base');
insert into plan_workouts (week_id, scheduled_date, kind, completed_run_id) values
  ('aaaaaaaa-0000-0000-0000-0000000000c6', current_date, 'easy', 'aaaaaaaa-0000-0000-0000-0000000000f1'),
  ('aaaaaaaa-0000-0000-0000-0000000000c6', current_date + 1, 'tempo', null),
  ('aaaaaaaa-0000-0000-0000-0000000000c6', current_date + 2, 'rest', null);

set local role authenticated;

-- ============================================================
-- As the coach: exactly Athlete A's row, with correct aggregates.
-- ============================================================
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c1","role":"authenticated"}';

select is(
  (select count(*)::int from coach_roster_summary()),
  1, 'roster returns exactly one row (the active link, not the ended one)');

select is(
  (select athlete_id from coach_roster_summary()),
  'aaaaaaaa-0000-0000-0000-0000000000a1'::uuid,
  'the single row is the actively-linked athlete A');

select is(
  (select runs_7d from coach_roster_summary()),
  2, 'runs_7d counts the two last-7-day runs, excluding the 20-day-old + the DNF');

select is(
  (select distance_7d_m from coach_roster_summary()),
  13000::double precision, 'distance_7d_m sums only the two valid 7-day runs (5000 + 8000)');

select ok(
  (select load_acute from coach_roster_summary()) > 0,
  'load_acute is positive for an athlete who ran in the last 7 days');

select ok(
  (select load_chronic from coach_roster_summary()) > 0,
  'load_chronic is positive (28-day window includes the older run)');

select is(
  (select plan_completion_pct from coach_roster_summary()),
  50, 'plan_completion_pct = 50 (1 done of 2 non-rest, non-skipped workouts)');

-- ============================================================
-- A non-coach sees an empty roster (the mine CTE is the only gate).
-- ============================================================
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000e1","role":"authenticated"}';
select is(
  (select count(*)::int from coach_roster_summary()),
  0, 'a non-coach gets zero roster rows');

-- The athlete is not a coach of their own coach (directional gate).
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000a1","role":"authenticated"}';
select is(
  (select count(*)::int from coach_roster_summary()),
  0, 'an athlete is not a coach -- their roster is empty');

-- ============================================================
-- Anon / unauthenticated: the function raises (fail-closed).
-- ============================================================
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
select throws_ok(
  $$select * from coach_roster_summary()$$,
  'not authenticated',
  'coach_roster_summary raises for an unauthenticated caller');

-- ============================================================
-- Ending the active link revokes the athlete from the roster immediately.
-- Flip status as superuser (the ending mechanism is #46's contract).
-- ============================================================
reset role;
update coach_athletes set status = 'ended', ended_at = now()
  where coach_id = 'aaaaaaaa-0000-0000-0000-0000000000c1'
    and athlete_id = 'aaaaaaaa-0000-0000-0000-0000000000a1';

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c1","role":"authenticated"}';
select is(
  (select count(*)::int from coach_roster_summary()),
  0, 'ending the last active link empties the coach roster');

-- ============================================================
-- A coach with only a PENDING (unredeemed) invite gets no rows -- a pending
-- invite is not consent.
-- ============================================================
reset role;
insert into coach_athletes (coach_id, status, invite_token)
  values ('aaaaaaaa-0000-0000-0000-0000000000c1', 'pending', 'crs-tok-pending');
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c1","role":"authenticated"}';
select is(
  (select count(*)::int from coach_roster_summary()),
  0, 'a pending invite (unredeemed) contributes no roster row');

select is(
  (select count(*)::int from coach_roster_summary()),
  0, 'roster is still empty -- pending is not active consent');

select * from finish();
rollback;
