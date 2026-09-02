-- challenges_goal_ck (migration 20270615_001).
--
-- Proves the two shapes the constraint refuses, the streak ceiling it computes,
-- and — the half that is easy to over-reach — the three metrics it deliberately
-- leaves unbounded. A `duration` goal longer than its own window is REACHABLE
-- (the aggregate sums duration_s over runs whose START is inside the window, so
-- a run begun a minute before it closes carries its whole duration), and a
-- constraint that refused it would refuse a legitimate ultra challenge.

begin;

select plan(13);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-0000c9000001', 'authenticated', 'authenticated',
        'goal-ck@spam.local', '', now(), now());

insert into user_profiles (id, display_name)
values ('00000000-0000-0000-0000-0000c9000001', 'Gia')
on conflict (id) do nothing;

-- ── goal_value > 0 ──────────────────────────────────────────────────────────
-- A stored 0 is not an inert "no goal": recompute_challenge_completion returns
-- early only on NULL, then compares `value >= goal`, so 0 >= 0 awards the badge
-- to every participant on the nightly sweep while both clients render the board
-- as goal-less.
select throws_ok(
  $$insert into challenges (creator_id, title, metric, scope, goal_value, starts_at, ends_at)
      values ('00000000-0000-0000-0000-0000c9000001', 'GK zero', 'distance',
              'individual', 0, '2027-01-01 00:00:00+00', '2027-01-31 00:00:00+00')$$,
  '23514',
  null,
  'a zero goal is refused'
);

select throws_ok(
  $$insert into challenges (creator_id, title, metric, scope, goal_value, starts_at, ends_at)
      values ('00000000-0000-0000-0000-0000c9000001', 'GK neg', 'distance',
              'individual', -5, '2027-01-01 00:00:00+00', '2027-01-31 00:00:00+00')$$,
  '23514',
  null,
  'a negative goal is refused'
);

select lives_ok(
  $$insert into challenges (id, creator_id, title, metric, scope, goal_value, starts_at, ends_at)
      values ('e9000000-0000-0000-0000-000000000001',
              '00000000-0000-0000-0000-0000c9000001', 'GK null', 'distance',
              'individual', null, '2027-01-01 00:00:00+00', '2027-01-31 00:00:00+00')$$,
  'a goal-less (pure-ranking) board is still allowed'
);

-- ── the non-finite goals ────────────────────────────────────────────────────
-- `NaN > 0` is TRUE for numeric — Postgres orders NaN above every real value
-- rather than making the comparison unknown — so the `goal_value > 0` term
-- alone admitted one, and `goal_value` is bare `numeric`, which holds Infinity
-- as well. Both are silent: `recompute_challenge_completion` compares
-- `value >= goal`, which is false forever against NaN and against Infinity, so
-- the challenge is unwinnable and nothing on either client says so. The
-- client half already refuses a non-finite goal (`Number.isFinite` in
-- `checkChallengeGoal`), so the two halves disagreed about a row that could
-- exist. Migration 20270704000002 added the two terms; these are the
-- by-value pins the schema-wide sweep in numeric_bounds_reject_nan_test.sql
-- exempts this column in favour of.
select throws_ok(
  $$insert into challenges (creator_id, title, metric, scope, goal_value, starts_at, ends_at)
      values ('00000000-0000-0000-0000-0000c9000001', 'GK nan', 'distance',
              'individual', 'NaN', '2027-01-01 00:00:00+00', '2027-01-31 00:00:00+00')$$,
  '23514',
  null,
  'a NaN goal is refused — NaN > 0 is true, so the positivity term alone let it in'
);

select throws_ok(
  $$insert into challenges (creator_id, title, metric, scope, goal_value, starts_at, ends_at)
      values ('00000000-0000-0000-0000-0000c9000001', 'GK inf', 'distance',
              'individual', 'Infinity', '2027-01-01 00:00:00+00', '2027-01-31 00:00:00+00')$$,
  '23514',
  null,
  'an infinite goal is refused — the column is bare numeric and holds one'
);

-- The same value arriving through the edit path.
select throws_ok(
  $$update challenges set goal_value = 'NaN'
      where id = 'e9000000-0000-0000-0000-000000000001'$$,
  '23514',
  null,
  'a NaN goal is refused on UPDATE, not only on INSERT'
);

-- The reason the terms are spelled out rather than left to `> 0`.
select ok(
  ('NaN'::numeric > 0),
  'NaN passes a bare positivity test, which is why the constraint names it'
);

-- ── streak_days ceiling ─────────────────────────────────────────────────────
-- A 30-day window (Jan 1 → Jan 31) opening at midnight touches 30 dates, but
-- the constraint uses the loose floor(seconds / 86400) + 1 = 31 ceiling so a
-- window shifted off midnight is never refused a day it could actually count.
select lives_ok(
  $$insert into challenges (id, creator_id, title, metric, scope, goal_value, starts_at, ends_at)
      values ('e9000000-0000-0000-0000-000000000002',
              '00000000-0000-0000-0000-0000c9000001', 'GK streak fits', 'streak_days',
              'individual', 31, '2027-01-01 00:00:00+00', '2027-01-31 00:00:00+00')$$,
  'a streak goal at the window ceiling is allowed'
);

select throws_ok(
  $$insert into challenges (creator_id, title, metric, scope, goal_value, starts_at, ends_at)
      values ('00000000-0000-0000-0000-0000c9000001', 'GK streak over', 'streak_days',
              'individual', 32, '2027-01-01 00:00:00+00', '2027-01-31 00:00:00+00')$$,
  '23514',
  null,
  'a streak goal one day past the ceiling is refused'
);

-- Shrinking the window under a goal that already fits is the same defect
-- arriving through the edit path, so the constraint has to catch the UPDATE.
select throws_ok(
  $$update challenges set ends_at = '2027-01-08 00:00:00+00'
      where id = 'e9000000-0000-0000-0000-000000000002'$$,
  '23514',
  null,
  'shrinking the window under an existing streak goal is refused'
);

-- ── the metrics the window does NOT bound ───────────────────────────────────
select lives_ok(
  $$insert into challenges (creator_id, title, metric, scope, goal_value, starts_at, ends_at)
      values ('00000000-0000-0000-0000-0000c9000001', 'GK moab', 'duration',
              'individual', 403200, '2027-01-01 00:00:00+00', '2027-01-02 00:00:00+00')$$,
  'a 112-hour duration goal in a one-day window is allowed — the sum is not window-bounded'
);

select lives_ok(
  $$insert into challenges (creator_id, title, metric, scope, goal_value, starts_at, ends_at)
      values ('00000000-0000-0000-0000-0000c9000001', 'GK count', 'activity_count',
              'individual', 500, '2027-01-01 00:00:00+00', '2027-01-02 00:00:00+00')$$,
  'an activity_count goal far above the window day count is allowed'
);

select lives_ok(
  $$insert into challenges (creator_id, title, metric, scope, goal_value, starts_at, ends_at)
      values ('00000000-0000-0000-0000-0000c9000001', 'GK vert', 'vert',
              'individual', 100000, '2027-01-01 00:00:00+00', '2027-01-02 00:00:00+00')$$,
  'a vert goal is unbounded by the window'
);

select finish();
rollback;
