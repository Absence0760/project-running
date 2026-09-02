-- runs_distance_m_check / runs_duration_s_check / runs_elevation_gain_m_check
-- (migration 20270704000001).
--
-- Written from the ordinary `authenticated` seat on purpose. The attacker here
-- is not a service-role caller or a hand-run repair: it is any signed-in
-- account writing its OWN run through the self-owned INSERT policy, which is
-- the only privilege the exploit needs. Measured over PostgREST with a
-- password-grant JWT before the constraints existed — `{"distance_m":"NaN"}`
-- stored verbatim and returned 201.
--
-- The NaN cases are the load-bearing half. `'NaN'::numeric >= 0` is TRUE in
-- Postgres, so a bound written as a bare `distance_m >= 0` admits every one of
-- them; the first assertion below pins that fact so the reason the constraint
-- is spelled the way it is cannot be forgotten and quietly simplified away.
--
-- Coverage this suite does NOT claim: it says nothing about an absurd-but-real
-- distance. There is deliberately no upper bound (a 240-mile ultra is 386 km),
-- so a 40,000 km run is still storable — it is merely no longer able to make
-- every aggregate that touches it return NaN.

begin;

select plan(16);

-- ── the Postgres fact the constraint is shaped around ───────────────────────
select ok(
  ('NaN'::numeric >= 0),
  'NaN passes a bare >= 0 numeric bound, which is why the constraint names it'
);
select ok(
  ('NaN'::numeric > 1e9::numeric),
  'NaN outranks every real value, so a descending rank puts it first'
);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('d0000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'bounds-runs@spam.local', '', now(), now());

insert into user_profiles (id, display_name, preferred_unit)
values ('d0000000-0000-0000-0000-000000000001', 'Bounds Runs', 'km')
on conflict (id) do nothing;

select tests.confirm_consent();

set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"d0000000-0000-0000-0000-000000000001","role":"authenticated"}';

-- ── distance_m ──────────────────────────────────────────────────────────────
select lives_ok(
  $$ insert into runs (id, user_id, started_at, duration_s, distance_m, source,
                       activity_type, metadata)
     values ('d0000000-0000-0000-0000-00000000a001',
             'd0000000-0000-0000-0000-000000000001', now(), 1800, 5000, 'app',
             'run', '{"activity_type":"run"}') $$,
  'an ordinary 5 km run still stores'
);
select lives_ok(
  $$ insert into runs (id, user_id, started_at, duration_s, distance_m, source,
                       activity_type, metadata)
     values ('d0000000-0000-0000-0000-00000000a002',
             'd0000000-0000-0000-0000-000000000001', now(), 1800, 0, 'app',
             'run', '{"activity_type":"run"}') $$,
  'a zero-distance run is accepted at the floor — a treadmill row is one'
);
select throws_ok(
  $$ insert into runs (id, user_id, started_at, duration_s, distance_m, source,
                       activity_type, metadata)
     values ('d0000000-0000-0000-0000-00000000a003',
             'd0000000-0000-0000-0000-000000000001', now(), 1800, -0.01, 'app',
             'run', '{"activity_type":"run"}') $$,
  '23514', null,
  'one centimetre below zero is rejected'
);
select throws_ok(
  $$ insert into runs (id, user_id, started_at, duration_s, distance_m, source,
                       activity_type, metadata)
     values ('d0000000-0000-0000-0000-00000000a004',
             'd0000000-0000-0000-0000-000000000001', now(), 1800, 'NaN', 'app',
             'run', '{"activity_type":"run"}') $$,
  '23514', null,
  'a NaN distance is rejected — the challenge-leaderboard exploit'
);
select throws_ok(
  $$ update runs set distance_m = 'NaN'
      where id = 'd0000000-0000-0000-0000-00000000a001' $$,
  '23514', null,
  'the same value is refused on UPDATE, not only on INSERT'
);

-- ── duration_s ──────────────────────────────────────────────────────────────
select lives_ok(
  $$ insert into runs (id, user_id, started_at, duration_s, distance_m, source,
                       activity_type, metadata)
     values ('d0000000-0000-0000-0000-00000000a005',
             'd0000000-0000-0000-0000-000000000001', now(), 0, 1200, 'app',
             'run', '{"activity_type":"run"}') $$,
  'a zero duration is accepted at the floor'
);
select throws_ok(
  $$ insert into runs (id, user_id, started_at, duration_s, distance_m, source,
                       activity_type, metadata)
     values ('d0000000-0000-0000-0000-00000000a006',
             'd0000000-0000-0000-0000-000000000001', now(), -1, 5000, 'app',
             'run', '{"activity_type":"run"}') $$,
  '23514', null,
  'one second below zero is rejected — it would be the account 5k best'
);

-- ── elevation_gain_m ────────────────────────────────────────────────────────
select lives_ok(
  $$ update runs set elevation_gain_m = 0
      where id = 'd0000000-0000-0000-0000-00000000a001' $$,
  'a flat run records zero ascent'
);
select lives_ok(
  $$ update runs set elevation_gain_m = null
      where id = 'd0000000-0000-0000-0000-00000000a001' $$,
  'an unknown ascent is still null — the column stays optional'
);
select throws_ok(
  $$ update runs set elevation_gain_m = -1
      where id = 'd0000000-0000-0000-0000-00000000a001' $$,
  '23514', null,
  'a negative ascent is rejected — gain is a sum of positive deltas'
);
select throws_ok(
  $$ update runs set elevation_gain_m = 'NaN'
      where id = 'd0000000-0000-0000-0000-00000000a001' $$,
  '23514', null,
  'a NaN ascent is rejected'
);
select throws_ok(
  $$ update runs set elevation_gain_m = 'Infinity'
      where id = 'd0000000-0000-0000-0000-00000000a001' $$,
  '23514', null,
  'an infinite ascent is rejected — the column is bare numeric and holds one'
);

-- ── the consequence, measured rather than asserted ──────────────────────────
-- distance_m is numeric(10, 2), whose scale refuses an infinite value with a
-- 22003 field overflow rather than the 23514 the constraint would raise. That
-- is why the distance bound carries no infinity term: it would be dead code.
select throws_ok(
  $$ insert into runs (id, user_id, started_at, duration_s, distance_m, source,
                       activity_type, metadata)
     values ('d0000000-0000-0000-0000-00000000a007',
             'd0000000-0000-0000-0000-000000000001', now(), 60, 'Infinity', 'app',
             'run', '{"activity_type":"run"}') $$,
  '22003', null,
  'an infinite distance is refused by the column scale, before any CHECK'
);

-- The personal-records refresher orders its whole-run branch by duration_s
-- ascending with no floor of its own, so the constraint above is the only
-- thing standing between a negative duration and the account best. With the
-- honest rows only, the cache says what the runs say.
select is(
  (select best_time_s from personal_records
    where user_id = 'd0000000-0000-0000-0000-000000000001' and distance = '5k'),
  1800,
  'the 5k best is the honest run, and no shorter row exists to displace it'
);

select * from finish();
rollback;
