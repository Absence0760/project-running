-- The bounds added by migrations 20270705000001 through 20270705000003, on the
-- numeric columns that had carried no CHECK at all.
--
-- 20270704000002 fixed every EXISTING numeric bound that admitted NaN. It could
-- say nothing about a column with no bound, and re-derived from the live
-- catalogue there were 79 of them — 31 in a type that can hold NaN. The eleven
-- taken first are the ones whose bad value is read by someone other than its
-- author.
--
-- The live-ping half is written from the ordinary `authenticated` seat, because
-- that is the whole exploit: no service key, no admin, no second account. The
-- runner writes a NaN coordinate to their OWN run through
-- `live_run_pings_insert_self`, and every spectator on `/live/[id]` reads it
-- back through `live_run_pings_visible_when_run_is`. Measured before the
-- constraints existed, from `set local role authenticated` with the owner's own
-- claims: `('NaN', 'Infinity', 'NaN', 'NaN', -5, -40)` inserted, and `set local
-- role anon` read all six values back. PostGIS did notice — inserting the row
-- raises `NOTICE: Coordinate values were coerced into range [-180 -90, 180 90]
-- for GEOGRAPHY` — but it clamped only its own derived geography point and left
-- the two float8 columns the clients read untouched. A notice is not a
-- constraint.
--
-- Coverage this suite does NOT claim: it says nothing about an absurd-but-real
-- value inside a bound. A 40,000 km `distance_m` is still storable, as
-- 20270704000001's suite records for `runs`. The claim here is narrower and
-- exact — the value is a number, and it is inside the domain its column names.

begin;

select plan(29);

-- ── the two Postgres facts the bounds are shaped around ────────────────────
select ok(
  ('NaN'::float8 >= 0),
  'NaN passes a bare >= 0 float8 bound, which is why each one-sided bound names it'
);
select ok(
  not ('NaN'::float8 <= 90),
  'and fails a two-sided one, which is why the lat/lng bounds need no NaN term'
);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('d1000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'bounds-unbounded@spam.local', '', now(), now());

insert into user_profiles (id, display_name, preferred_unit)
values ('d1000000-0000-0000-0000-000000000001', 'Bounds Unbounded', 'km')
on conflict (id) do nothing;

select tests.confirm_consent();

-- Fixtures the RLS INSERT policies require, built from the owning seat below
-- except for the race session, which only a race director arms.
insert into runs (id, user_id, started_at, duration_s, distance_m, source,
                  activity_type, is_public, metadata)
values ('d1000000-0000-0000-0000-00000000a001',
        'd1000000-0000-0000-0000-000000000001', now(), 1800, 5000, 'app',
        'run', true, '{"activity_type":"run"}');

insert into clubs (id, owner_id, name, slug, is_public)
values ('d1000000-0000-0000-0000-00000000c001',
        'd1000000-0000-0000-0000-000000000001', 'Bounds Club', 'bounds-club', true);

insert into events (id, club_id, title, starts_at, author_id, category, is_public)
values ('d1000000-0000-0000-0000-00000000e001',
        'd1000000-0000-0000-0000-00000000c001', 'Bounds Race', now(),
        'd1000000-0000-0000-0000-000000000001', 'run', true);

insert into race_sessions (event_id, instance_start, status, started_at, started_by)
values ('d1000000-0000-0000-0000-00000000e001',
        '2026-09-03T09:00:00Z', 'running', now(),
        'd1000000-0000-0000-0000-000000000001');

set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"d1000000-0000-0000-0000-000000000001","role":"authenticated"}';

-- ── live_run_pings: the anonymous-spectator surface ────────────────────────
select lives_ok(
  $$ insert into live_run_pings (run_id, user_id, lat, lng, ele, distance_m,
                                 elapsed_s, bpm)
     values ('d1000000-0000-0000-0000-00000000a001',
             'd1000000-0000-0000-0000-000000000001',
             51.5, -0.12, 35, 1200, 400, 148) $$,
  'an ordinary live ping still stores'
);
select throws_ok(
  $$ insert into live_run_pings (run_id, user_id, lat, lng)
     values ('d1000000-0000-0000-0000-00000000a001',
             'd1000000-0000-0000-0000-000000000001', 'NaN', 0) $$,
  '23514', null,
  'a NaN latitude is rejected — the coordinate that draws nothing on the map'
);
select throws_ok(
  $$ insert into live_run_pings (run_id, user_id, lat, lng)
     values ('d1000000-0000-0000-0000-00000000a001',
             'd1000000-0000-0000-0000-000000000001', 91, 0) $$,
  '23514', null,
  'a latitude past the pole is rejected'
);
select throws_ok(
  $$ insert into live_run_pings (run_id, user_id, lat, lng)
     values ('d1000000-0000-0000-0000-00000000a001',
             'd1000000-0000-0000-0000-000000000001', 0, 'Infinity') $$,
  '23514', null,
  'an infinite longitude is rejected — it fit the spectator viewport to the world'
);
select throws_ok(
  $$ insert into live_run_pings (run_id, user_id, lat, lng, ele)
     values ('d1000000-0000-0000-0000-00000000a001',
             'd1000000-0000-0000-0000-000000000001', 0, 0, 'NaN') $$,
  '23514', null,
  'a NaN elevation is rejected by the two-sided bound, with no NaN term written'
);
select throws_ok(
  $$ insert into live_run_pings (run_id, user_id, lat, lng, ele)
     values ('d1000000-0000-0000-0000-00000000a001',
             'd1000000-0000-0000-0000-000000000001', 0, 0, 12000) $$,
  '23514', null,
  'an elevation above Everest is rejected'
);
select throws_ok(
  $$ insert into live_run_pings (run_id, user_id, lat, lng, distance_m)
     values ('d1000000-0000-0000-0000-00000000a001',
             'd1000000-0000-0000-0000-000000000001', 0, 0, 'NaN') $$,
  '23514', null,
  'a NaN odometer is rejected — motionFor reads its delta'
);
select throws_ok(
  $$ insert into live_run_pings (run_id, user_id, lat, lng, distance_m)
     values ('d1000000-0000-0000-0000-00000000a001',
             'd1000000-0000-0000-0000-000000000001', 0, 0, 'Infinity') $$,
  '23514', null,
  'an infinite odometer is rejected — float8 has no typmod to refuse it first'
);
select lives_ok(
  $$ insert into live_run_pings (run_id, user_id, lat, lng, distance_m, bpm)
     values ('d1000000-0000-0000-0000-00000000a001',
             'd1000000-0000-0000-0000-000000000001', 0, 0, 0, 0) $$,
  'a zero odometer and a zero bpm are accepted — the first ping, sensor off-wrist'
);
select throws_ok(
  $$ insert into live_run_pings (run_id, user_id, lat, lng, elapsed_s)
     values ('d1000000-0000-0000-0000-00000000a001',
             'd1000000-0000-0000-0000-000000000001', 0, 0, -5) $$,
  '23514', null,
  'a negative elapsed_s is rejected'
);
select throws_ok(
  $$ insert into live_run_pings (run_id, user_id, lat, lng, bpm)
     values ('d1000000-0000-0000-0000-00000000a001',
             'd1000000-0000-0000-0000-000000000001', 0, 0, -40) $$,
  '23514', null,
  'a negative heart rate is rejected'
);
select throws_ok(
  $$ insert into live_run_pings (run_id, user_id, lat, lng, bpm)
     values ('d1000000-0000-0000-0000-00000000a001',
             'd1000000-0000-0000-0000-000000000001', 0, 0, 301) $$,
  '23514', null,
  'a heart rate past any measured human one is rejected'
);
-- ── race_pings: the same surface, the race-director side ───────────────────
select lives_ok(
  $$ insert into race_pings (event_id, instance_start, user_id, at, lat, lng,
                             distance_m, elapsed_s, bpm, coarse)
     values ('d1000000-0000-0000-0000-00000000e001', '2026-09-03T09:00:00Z',
             'd1000000-0000-0000-0000-000000000001', now(), 51.5, -0.12,
             1200, 400, 148, false) $$,
  'an ordinary race ping still stores'
);
select throws_ok(
  $$ insert into race_pings (event_id, instance_start, user_id, at, lat, lng, coarse)
     values ('d1000000-0000-0000-0000-00000000e001', '2026-09-03T09:00:00Z',
             'd1000000-0000-0000-0000-000000000001', now(), 'NaN', 0, false) $$,
  '23514', null,
  'a NaN latitude is rejected on the race board too'
);
select throws_ok(
  $$ insert into race_pings (event_id, instance_start, user_id, at, lat, lng,
                             distance_m, coarse)
     values ('d1000000-0000-0000-0000-00000000e001', '2026-09-03T09:00:00Z',
             'd1000000-0000-0000-0000-000000000001', now(), 0, 0, 'Infinity', false) $$,
  '23514', null,
  'an infinite race odometer is rejected'
);

-- ── runs.fastest_*_s: the personal-record exploit, one column over ─────────
select lives_ok(
  $$ update runs set fastest_5k_s = 900
      where id = 'd1000000-0000-0000-0000-00000000a001' $$,
  'a real 15-minute embedded 5k still stores'
);
select throws_ok(
  $$ update runs set fastest_5k_s = 0
      where id = 'd1000000-0000-0000-0000-00000000a001' $$,
  '23514', null,
  'a zero-second embedded 5k is rejected — refresh_personal_records filters on >= 0'
);
select throws_ok(
  $$ update runs set fastest_marathon_s = -1
      where id = 'd1000000-0000-0000-0000-00000000a001' $$,
  '23514', null,
  'and a negative one, which would outrank every real marathon'
);

-- ── the rest of the never-bounded set, sampled per shape ───────────────────
select throws_ok(
  $$ insert into routes (user_id, name, waypoints, distance_m)
     values ('d1000000-0000-0000-0000-000000000001', 'Bad Route', '[]'::jsonb, 'NaN') $$,
  '23514', null,
  'a NaN route distance is rejected — it is the routes list sort key'
);
-- The two accepted inserts below carry an explicit `computed_at` on different
-- days: `fitness_snapshots_user_day_uniq` (20270710000002) holds one snapshot
-- per runner per UTC day, and both of these are the same runner. The subject
-- here is the column's own bounds, so the day is fixture bookkeeping — but it
-- has to be there, or the second insert fails on a constraint that is not
-- what this file is asserting.
select lives_ok(
  $$ insert into fitness_snapshots (user_id, source, computed_at, training_stress_bal, vo2_max)
     values ('d1000000-0000-0000-0000-000000000001', 'client', now() - interval '2 days', -25.5, 52) $$,
  'a negative training-stress balance is accepted — a runner mid-build has one'
);
select throws_ok(
  $$ insert into fitness_snapshots (user_id, source, training_stress_bal)
     values ('d1000000-0000-0000-0000-000000000001', 'client', 'NaN') $$,
  '23514', null,
  'but a NaN one is rejected, by the finiteness term that carries no range claim'
);
select throws_ok(
  $$ insert into fitness_snapshots (user_id, source, vo2_max)
     values ('d1000000-0000-0000-0000-000000000001', 'client', 150) $$,
  '23514', null,
  'a VO2 max past any recorded human one is rejected'
);
select lives_ok(
  $$ insert into fitness_snapshots (user_id, source, computed_at, vo2_max)
     values ('d1000000-0000-0000-0000-000000000001', 'client', now() - interval '1 day', 90) $$,
  'and the column stays wider than vdotFromRun''s own 90 ceiling, so no shipped writer hits it'
);

reset role;

-- ── the columns no client seat can reach ───────────────────────────────────
-- A CHECK applies to every role, so these are asserted from the elevated seat.
-- `gym_workouts.volume_kg` and `personal_records.best_time_s` are both
-- server-maintained: the first is zeroed for `authenticated` by
-- `freeze_gym_workout_managed_columns` (20270704000003) and the second carries
-- no client grant at all, so the constraint is the second line rather than the
-- first — it holds against the trigger's own arithmetic and against a hand-run
-- repair, which is where a bad aggregate would come from now.
select throws_ok(
  $$ update events set meet_lat = 91
      where id = 'd1000000-0000-0000-0000-00000000e001' $$,
  '23514', null,
  'a meeting point past the pole is rejected'
);
select throws_ok(
  $$ update events set meet_lng = 'NaN'
      where id = 'd1000000-0000-0000-0000-00000000e001' $$,
  '23514', null,
  'and a NaN meeting longitude'
);

select throws_ok(
  $$ insert into gym_workouts (user_id, volume_kg) values
     ('d1000000-0000-0000-0000-000000000001', 'NaN') $$,
  '23514', null,
  'a NaN volume is rejected on the derived cache the /gym list reads'
);
select throws_ok(
  $$ insert into personal_records (user_id, distance, best_time_s, achieved_at)
     values ('d1000000-0000-0000-0000-000000000001', '5k', 0, now()) $$,
  '23514', null,
  'a zero-second personal record is rejected'
);

select * from finish();
rollback;
