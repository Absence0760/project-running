-- runs.distance_m, runs.duration_s and runs.elevation_gain_m carried no bound
-- of any kind. Every one of them is a physical measurement that only the
-- clients ever graded, and at least one client was written believing the
-- database graded it too: `CsvRunImporter` passed a negative distance straight
-- through under a comment naming "the DB CHECK (distance_m >= 0, duration_s >=
-- 0)" as the source of truth. Those CHECKs are on `event_results` and
-- `gym_workouts`. `runs` has neither.
--
-- Measured against the local stack on 2026-09-02, signed in over PostgREST as
-- the seeded runner with an ordinary password-grant JWT — no service role, no
-- admin path, nothing but the self-owned INSERT policy every account has:
--
--   POST /rest/v1/runs
--   {"distance_m":"NaN","duration_s":-60,"elevation_gain_m":"Infinity", ...}
--   -> 201, row stored verbatim
--
-- `numeric` holds NaN, and PostgREST coerces the JSON string "NaN" into it.
-- Two consequences, both reachable by any authenticated user against shared
-- state rather than only their own:
--
--   * NaN sorts ABOVE every real number in Postgres numeric ordering, and
--     `challenge_leaderboard` ranks on `rank() over (order by value desc)`
--     over `sum(r.distance_m)`. One NaN run inside the window puts its author
--     at rank 1 of every distance challenge they have joined, ahead of a
--     genuine 90 km. `sum(coalesce(elevation_gain_m, 0))` is the same story
--     for a `vert` challenge, where the column's bare `numeric` type accepts
--     Infinity as well.
--
--   * a negative `duration_s` is a personal record. The whole-run branch of
--     `refresh_personal_records_for_user` filters `distance_m is not null and
--     duration_s is not null` and orders by `duration_s asc`; the promoted
--     `fastest_*_s` branches already carry a `>= 0` floor, but the branch that
--     reads the run's own duration does not. A 5 km run stamped -500 s becomes
--     the account's 5k best.
--
-- `distance_m` is `numeric(10, 2)`, whose scale refuses Infinity outright
-- ("a field with precision 10, scale 2 cannot hold an infinite value") but
-- accepts NaN, so the NaN term is what the bound needs and the infinity term
-- would be dead. `elevation_gain_m` is bare `numeric` and accepts both, so it
-- carries the third term. `duration_s` is `integer` and needs neither.
--
-- A plain `>= 0` is NOT enough on a numeric column: `'NaN'::numeric >= 0` is
-- true. The NaN term is the load-bearing half of the distance bound, not
-- decoration.
--
-- No upper bound. The honest ceiling for a single activity is not a number
-- this schema knows — a 240-mile ultra is 386 km and a multi-day push is
-- longer still — and refusing a real measurement is worse than admitting an
-- absurd one that no longer poisons an aggregate.
--
-- Not registered in `check_constraint_unions.mjs`: its PAIRS coverage rule
-- reads `check (col in (…))` clauses only, and an entry naming a column with
-- no set-shaped CHECK fails the guard rather than satisfying it.
--
-- Online-safety (docs/backend/migration_locks.md): `runs` is the highest-volume
-- table in the schema, so each constraint is added `NOT VALID` — a metadata
-- flip under a brief ACCESS EXCLUSIVE, no scan — and validated separately under
-- SHARE UPDATE EXCLUSIVE, where readers and writers proceed.
--
-- The repair below runs BEFORE the validation because an out-of-range row here
-- is bad data, not an attack artifact, and aborting a production deploy on one
-- is worse than correcting it. Each UPDATE is predicate-scoped to the rows that
-- actually violate, so on a healthy database it matches nothing and rewrites
-- nothing. Run these first to see what would move:
--
--   select count(*) from runs where distance_m < 0 or distance_m = 'NaN';
--   select count(*) from runs where duration_s < 0;
--   select count(*) from runs
--    where elevation_gain_m < 0 or elevation_gain_m = 'NaN'
--       or elevation_gain_m = 'Infinity';
--
-- distance_m and duration_s are NOT NULL, so the repair is 0 — a run that
-- covered no measurable ground, which is a shape the schema already holds for
-- a treadmill row. elevation_gain_m is nullable, so its repair is NULL, which
-- is the honest value: unknown, not zero.

update runs set distance_m = 0
 where distance_m < 0 or distance_m = 'NaN'::numeric;

update runs set duration_s = 0
 where duration_s < 0;

update runs set elevation_gain_m = null
 where elevation_gain_m < 0
    or elevation_gain_m = 'NaN'::numeric
    or elevation_gain_m = 'Infinity'::numeric;

alter table runs
  add constraint runs_distance_m_check
  check (distance_m >= 0 and distance_m <> 'NaN'::numeric)
  not valid;

alter table runs
  add constraint runs_duration_s_check
  check (duration_s >= 0)
  not valid;

alter table runs
  add constraint runs_elevation_gain_m_check
  check (
    elevation_gain_m is null
    or (
      elevation_gain_m >= 0
      and elevation_gain_m <> 'NaN'::numeric
      and elevation_gain_m <> 'Infinity'::numeric
    )
  ) not valid;

alter table runs validate constraint runs_distance_m_check;
alter table runs validate constraint runs_duration_s_check;
alter table runs validate constraint runs_elevation_gain_m_check;

comment on constraint runs_distance_m_check on runs is
  'A run covers a non-negative, real distance. The NaN term is load-bearing: '
  'NaN >= 0 is true for numeric and NaN outranks every real value in a '
  'descending sort, so one NaN run topped every distance challenge board.';

comment on constraint runs_duration_s_check on runs is
  'A run lasts a non-negative number of seconds. refresh_personal_records_for_user '
  'orders the whole-run branch by duration_s ascending with no floor of its own.';

comment on constraint runs_elevation_gain_m_check on runs is
  'Ascent is non-negative and finite. The column is bare numeric, so it accepts '
  'Infinity as well as NaN, and the vert challenge aggregate sums it.';
