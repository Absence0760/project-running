-- Pins the STRUCTURAL cache invariants of the `personal_records` summary
-- table + its `runs` triggers (migration 20260508_001_personal_records_cache,
-- as amended through 20261021_001). The sibling files
-- (personal_records_brackets/_dnf/_embedded_bests/_mile_test) pin the
-- bracket / candidate-selection *logic* but each calls
-- `refresh_personal_records_for_user(...)` directly, so none of them
-- actually exercise the cache contract: that the table is kept in sync by
-- the `runs` triggers, holds exactly one row per (user, distance), and is
-- writable ONLY through the trigger path. This file pins those.
--
-- Invariants under test (from the cache migration's header):
--   - INSERT/UPDATE/DELETE on `runs` recompute the cache automatically via
--     the AFTER statement triggers (per-row until 20270315_001) — no manual
--     refresh call.
--   - Exactly one row per (user_id, distance); the best (lowest
--     duration_s) qualifying run wins and a slower run never shadows it.
--   - Deleting the run that currently holds the PB promotes the next-best
--     run; deleting the last qualifying run removes the PB row entirely
--     (no dangling null-run_id remnant).
--   - "Writes come only from the trigger" — there is no user-level
--     INSERT/UPDATE/DELETE RLS policy, so an authenticated user cannot
--     forge or tamper with a PB row directly.
--   - Reads are owner-scoped: a user never sees another user's PB rows.
--
-- Everything below drives the cache through the triggers (never through a
-- direct refresh call) so a regression that detaches a trigger, or relaxes
-- the write-deny, fails here. The statement triggers fire synchronously
-- inside this transaction, so each assertion observes a settled cache.

begin;

select plan(17);

-- ── Fixture ── two users; auth.users seeded as the default (superuser)
-- role before we drop to `authenticated`, since auth.users is not
-- writable under RLS.
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('0c1d0000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated',
   'prc-a@test.local', '', now(), now()),
  ('0c1d0000-0000-0000-0000-0000000000b2', 'authenticated', 'authenticated',
   'prc-b@test.local', '', now(), now());

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"0c1d0000-0000-0000-0000-0000000000a1","role":"authenticated"}';

-- ── 1. Trigger creates the cache row on INSERT (no manual refresh) ──
insert into runs (id, user_id, started_at, duration_s, distance_m, source, metadata)
values ('0c1d0001-0000-0000-0000-000000000001',
        '0c1d0000-0000-0000-0000-0000000000a1',
        '2026-04-01 09:00:00+00', 1200, 5000, 'app', '{"activity_type":"run"}');

select is(
  (select count(*)::int from personal_records
   where user_id = '0c1d0000-0000-0000-0000-0000000000a1' and distance = '5k'),
  1,
  'INSERT trigger creates the 5k PB row with no manual refresh call'
);
select is(
  (select best_time_s from personal_records
   where user_id = '0c1d0000-0000-0000-0000-0000000000a1' and distance = '5k'),
  1200,
  'cached best_time_s reflects the only qualifying run'
);
select is(
  (select run_id from personal_records
   where user_id = '0c1d0000-0000-0000-0000-0000000000a1' and distance = '5k'),
  '0c1d0001-0000-0000-0000-000000000001'::uuid,
  'cached run_id points at the run that holds the PB'
);

-- ── 2. A faster run wins; one-row-per-distance holds ──
insert into runs (id, user_id, started_at, duration_s, distance_m, source, metadata)
values ('0c1d0001-0000-0000-0000-000000000002',
        '0c1d0000-0000-0000-0000-0000000000a1',
        '2026-04-08 09:00:00+00', 1100, 5000, 'app', '{"activity_type":"run"}');

select is(
  (select best_time_s from personal_records
   where user_id = '0c1d0000-0000-0000-0000-0000000000a1' and distance = '5k'),
  1100,
  'a faster 5k run becomes the PB after its INSERT trigger fires'
);
select is(
  (select run_id from personal_records
   where user_id = '0c1d0000-0000-0000-0000-0000000000a1' and distance = '5k'),
  '0c1d0001-0000-0000-0000-000000000002'::uuid,
  'cache run_id moves to the faster run'
);
select is(
  (select count(*)::int from personal_records
   where user_id = '0c1d0000-0000-0000-0000-0000000000a1' and distance = '5k'),
  1,
  'still exactly one 5k row — two qualifying runs collapse to the best'
);

-- ── 3. A slower run never shadows the PB ──
insert into runs (id, user_id, started_at, duration_s, distance_m, source, metadata)
values ('0c1d0001-0000-0000-0000-000000000003',
        '0c1d0000-0000-0000-0000-0000000000a1',
        '2026-04-15 09:00:00+00', 1300, 5000, 'app', '{"activity_type":"run"}');

select is(
  (select best_time_s from personal_records
   where user_id = '0c1d0000-0000-0000-0000-0000000000a1' and distance = '5k'),
  1100,
  'a slower 5k run does not displace the existing PB'
);
select is(
  (select count(*)::int from personal_records
   where user_id = '0c1d0000-0000-0000-0000-0000000000a1' and distance = '5k'),
  1,
  'still exactly one 5k row after the slower run'
);

-- ── 4. UPDATE re-ranks the cache ── slow the current PB run (run 2:
-- 1100 → 1400). The remaining best is run 1 (1200). The update trigger
-- (fires on duration_s) must demote run 2 and promote run 1.
update runs set duration_s = 1400
  where id = '0c1d0001-0000-0000-0000-000000000002';

select is(
  (select best_time_s from personal_records
   where user_id = '0c1d0000-0000-0000-0000-0000000000a1' and distance = '5k'),
  1200,
  'UPDATE trigger re-ranks: slowing the PB run promotes the next-best'
);
select is(
  (select run_id from personal_records
   where user_id = '0c1d0000-0000-0000-0000-0000000000a1' and distance = '5k'),
  '0c1d0001-0000-0000-0000-000000000001'::uuid,
  'cache run_id moves to the new best after the UPDATE'
);

-- ── 5. DELETE promotes the next-best ── runs now: run1=1200, run2=1400,
-- run3=1300; PB is run1. Delete run1; the next-best is run3 (1300).
delete from runs where id = '0c1d0001-0000-0000-0000-000000000001';

select is(
  (select best_time_s from personal_records
   where user_id = '0c1d0000-0000-0000-0000-0000000000a1' and distance = '5k'),
  1300,
  'DELETE trigger promotes the next-best run when the PB run is removed'
);
select is(
  (select run_id from personal_records
   where user_id = '0c1d0000-0000-0000-0000-0000000000a1' and distance = '5k'),
  '0c1d0001-0000-0000-0000-000000000003'::uuid,
  'cache run_id points at the promoted next-best run (no dangling null)'
);

-- ── 6. Deleting the last qualifying runs removes the PB row ──
delete from runs
  where id in ('0c1d0001-0000-0000-0000-000000000002',
               '0c1d0001-0000-0000-0000-000000000003');

select is(
  (select count(*)::int from personal_records
   where user_id = '0c1d0000-0000-0000-0000-0000000000a1' and distance = '5k'),
  0,
  'removing the last qualifying run deletes the PB row entirely'
);

-- ── 7. Writes come only from the trigger ── no user-level write policy,
-- so a direct INSERT by the authenticated owner is denied by RLS. This is
-- what keeps the cache an honest reflection of `runs` rather than a
-- forgeable scoreboard.
select throws_ok(
  $$ insert into personal_records (user_id, distance, best_time_s, achieved_at)
       values ('0c1d0000-0000-0000-0000-0000000000a1', '5k', 1, now()) $$,
  '42501',
  null,
  'authenticated user cannot directly INSERT a forged PB row'
);

-- Declarative backstop: the table carries a SELECT policy but NO
-- INSERT/UPDATE/DELETE/ALL policy. Pins the "trigger-only writes" design
-- even if a future SELECT-policy edit accidentally widens the cmd.
select is(
  (select count(*)::int from pg_policies
   where schemaname = 'public' and tablename = 'personal_records'
     and cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL')),
  0,
  'personal_records exposes no user-level write policy (writes are trigger-only)'
);

-- ── 8. Reads are owner-scoped ── give user B a PB, then confirm user A
-- cannot see it.
set local "request.jwt.claims" = '{"sub":"0c1d0000-0000-0000-0000-0000000000b2","role":"authenticated"}';
insert into runs (id, user_id, started_at, duration_s, distance_m, source, metadata)
values ('0c1d0002-0000-0000-0000-000000000004',
        '0c1d0000-0000-0000-0000-0000000000b2',
        '2026-04-01 09:00:00+00', 999, 5000, 'app', '{"activity_type":"run"}');

select is(
  (select count(*)::int from personal_records
   where user_id = '0c1d0000-0000-0000-0000-0000000000b2' and distance = '5k'),
  1,
  'user B sees their own freshly-triggered PB row'
);

set local "request.jwt.claims" = '{"sub":"0c1d0000-0000-0000-0000-0000000000a1","role":"authenticated"}';
select is(
  (select count(*)::int from personal_records
   where user_id = '0c1d0000-0000-0000-0000-0000000000b2'),
  0,
  'user A cannot read user B PB rows (owner-scoped SELECT policy)'
);

select * from finish();

rollback;
