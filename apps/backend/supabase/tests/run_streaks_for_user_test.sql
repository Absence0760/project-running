-- pgtap suite for `run_streaks_for_user` (migration 20270501_001).
--
-- The RPC is the all-time source of truth behind the dashboard streak card's
-- sub-label (decisions § 471). These assertions pin the semantics against the
-- display-side computeRunStreaks helper (streaks.test.ts pins the other side):
-- local-day bucketing in the caller's zone, the Strava grace rule, the
-- future-day clamp, same-day dedupe, the source filter, and — the defect the
-- RPC exists to fix — a best streak that predates the dashboard's ~2-year
-- fetch window still reported at full length.
--
-- Fixture times that must land on a specific LOCAL day are built as local
-- noon in the test zone (`(<date> + time '12:00') at time zone <tz>`) so a
-- run near a DST transition or a suite running near midnight can't shift a
-- day. America/New_York is the test zone: UTC-5/-4, so a 23:30 local run is
-- the next UTC date.

begin;

select plan(12);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000b0001'::uuid, 'authenticated', 'authenticated',
   'streaker@streaks.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000b0002'::uuid, 'authenticated', 'authenticated',
   'nightowl@streaks.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000b0099'::uuid, 'authenticated', 'authenticated',
   'stranger@streaks.local', '', now(), now());

insert into user_profiles (id, display_name)
values
  ('00000000-0000-0000-0000-0000000b0001', 'Streaker'),
  ('00000000-0000-0000-0000-0000000b0002', 'Night Owl'),
  ('00000000-0000-0000-0000-0000000b0099', 'Stranger');

select tests.confirm_consent();

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000b0001"}';

-- Streaker's fixture, all 'app' unless noted:
--   * a 5-day island THREE YEARS ago (outside any client fetch window)
--   * a 3-day island ending local today (the current streak)
--   * two same-day runs on today (dedupe)
--   * one run tomorrow local noon (future clamp)
--   * a 2-day 'strava' island ending 10 days ago (source filter)
insert into runs (user_id, started_at, distance_m, duration_s, source, metadata)
select '00000000-0000-0000-0000-0000000b0001',
       ((current_date - interval '3 years')::date - offs + time '12:00') at time zone 'America/New_York',
       5000, 1500, 'app', '{"activity_type":"run"}'
from generate_series(0, 4) as offs;

insert into runs (user_id, started_at, distance_m, duration_s, source, metadata)
select '00000000-0000-0000-0000-0000000b0001',
       (((now() at time zone 'America/New_York')::date - offs) + time '12:00') at time zone 'America/New_York',
       5000, 1500, 'app', '{"activity_type":"run"}'
from generate_series(0, 2) as offs;

insert into runs (user_id, started_at, distance_m, duration_s, source, metadata)
values
  ('00000000-0000-0000-0000-0000000b0001',
   ((now() at time zone 'America/New_York')::date + time '13:00') at time zone 'America/New_York',
   3000, 900, 'app', '{"activity_type":"run"}'),
  ('00000000-0000-0000-0000-0000000b0001',
   (((now() at time zone 'America/New_York')::date + 1) + time '12:00') at time zone 'America/New_York',
   3000, 900, 'app', '{"activity_type":"run"}');

insert into runs (user_id, started_at, distance_m, duration_s, source, metadata)
select '00000000-0000-0000-0000-0000000b0001',
       (((now() at time zone 'America/New_York')::date - 10 - offs) + time '12:00') at time zone 'America/New_York',
       5000, 1500, 'strava', '{"activity_type":"run"}'
from generate_series(0, 1) as offs;

-- 1. Best streak is the PRE-WINDOW island (5), not the recent in-window 3 —
--    the windowed client compute this RPC replaces would report 3.
select is(
  (select best_streak from run_streaks_for_user('America/New_York')),
  5,
  'best streak counts an island older than any client fetch window'
);

-- 2. Current streak is the island ending today (3): same-day runs dedupe and
--    the future run does not extend it.
select is(
  (select current_streak from run_streaks_for_user('America/New_York')),
  3,
  'current streak dedupes same-day runs and clamps future-dated ones'
);

-- 3. Source filter scopes both figures: under 'strava' the best is the 2-day
--    island and the current streak is 0 (it ended 9 days ago).
select results_eq(
  $q$ select current_streak, best_streak from run_streaks_for_user('America/New_York', 'strava') $q$,
  $q$ values (0, 2) $q$,
  'p_source scopes the aggregate to one source'
);

-- 4. An unknown source yields zeros, not an error.
select results_eq(
  $q$ select current_streak, best_streak from run_streaks_for_user('America/New_York', 'nope') $q$,
  $q$ values (0, 0) $q$,
  'an unmatched source filter returns zeros'
);

-- Night Owl: a 23:30 local run on Jan 14 (UTC date Jan 15) and a 10:00
-- local run on Jan 16 (UTC date Jan 16). Local days are Jan 14 and Jan 16
-- (a gap); their UTC dates are Jan 15 and Jan 16 (consecutive). Local
-- bucketing must see two 1-day islands where a UTC bucketing would see one
-- 2-day streak.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000b0002"}';

insert into runs (user_id, started_at, distance_m, duration_s, source, metadata)
values
  ('00000000-0000-0000-0000-0000000b0002',
   (date '2026-01-14' + time '23:30') at time zone 'America/New_York',
   5000, 1500, 'app', '{"activity_type":"run"}'),
  ('00000000-0000-0000-0000-0000000b0002',
   (date '2026-01-16' + time '10:00') at time zone 'America/New_York',
   5000, 1500, 'app', '{"activity_type":"run"}');

-- 5. Bucketed in the runner's zone: two separate days with a gap → best 1.
select is(
  (select best_streak from run_streaks_for_user('America/New_York')),
  1,
  'a 23:30 local run buckets on its local day, not its UTC date'
);

-- 6. The same rows under UTC bucketing are consecutive → best 2. Pins that
--    p_tz is honoured (and documents exactly what the awarder's UTC shortcut
--    would get wrong).
select is(
  (select best_streak from run_streaks_for_user('UTC')),
  2,
  'p_tz drives the day bucketing'
);

-- 7. No current streak for Night Owl (last run was January).
select is(
  (select current_streak from run_streaks_for_user('America/New_York')),
  0,
  'a long-broken streak reports current = 0'
);

-- Grace rule: give Night Owl a 2-day island ending YESTERDAY (none today).
insert into runs (user_id, started_at, distance_m, duration_s, source, metadata)
select '00000000-0000-0000-0000-0000000b0002',
       (((now() at time zone 'America/New_York')::date - offs) + time '12:00') at time zone 'America/New_York',
       5000, 1500, 'app', '{"activity_type":"run"}'
from generate_series(1, 2) as offs;

-- 8. An island ending yesterday is still the current streak (Strava grace).
select is(
  (select current_streak from run_streaks_for_user('America/New_York')),
  2,
  'a streak ending yesterday survives the grace day'
);

-- 9. An unrecognized timezone raises for a caller WITH runs (a caller with
--    zero rows never evaluates the zone, so this must run as Night Owl).
--    The client treats the error as a failed fetch and suppresses the
--    all-time claim — fail-closed.
select throws_ok(
  $q$ select * from run_streaks_for_user('Not/AZone') $q$,
  '22023',
  null,
  'a bad timezone raises rather than silently bucketing wrong'
);

-- 10. A caller with no runs at all gets zeros, not NULLs.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000b0099"}';
select results_eq(
  $q$ select current_streak, best_streak from run_streaks_for_user('America/New_York') $q$,
  $q$ values (0, 0) $q$,
  'no runs → (0, 0)'
);

-- 11. Owner-scoped: the stranger's zeros above ARE the boundary — they never
--     see Streaker's days. Re-assert explicitly against 'app' (the source
--     with the most fixture rows).
select is(
  (select best_streak from run_streaks_for_user('America/New_York', 'app')),
  0,
  'a different user sees none of the streaker''s days (owner-scoped)'
);

-- 12. anon has no execute grant.
set local role anon;
set local "request.jwt.claims" = '{}';
select throws_ok(
  $q$ select * from run_streaks_for_user('UTC') $q$,
  '42501',
  null,
  'anon cannot execute the RPC'
);

select * from finish();
rollback;
