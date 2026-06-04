-- pgtap suite for `segment_leaderboard_tiered`.
--
-- Original migration: 20260829_001 (declared SECURITY INVOKER).
-- Forward fix:        20260830_001 (promoted to SECURITY DEFINER, strips
-- cross-user gender+age, drops anon grant, rejects null auth.uid()).
--
-- Covers:
--   1. Unfiltered call returns all efforts on the segment, ordered by time.
--   2. Tied times share the same client-side rank (server returns them
--      in a deterministic order, started_at as the tiebreaker).
--   3. Gender filter narrows to matching profiles only.
--   4. Age-band filter narrows to runners whose current age falls in
--      the bracket.
--   5. '75+' band is inclusive of every age >= 75.
--   6. Combined gender + age-band filter is an intersection.
--   7. Filter with zero matches returns zero rows (not an error).
--   8. No-demographics runners are invisible to age-band filters.
--   9. A stranger on a public-route segment can read the cohort.
--  10. A stranger on a private-route segment gets zero rows
--      (visibility filter mirrors RLS now that the function is
--      SECURITY DEFINER and bypasses RLS by default).
--  11. Malformed p_age_band raises 22023.
--  12. Cross-user rows in the leaderboard have NULL gender + age
--      (the privacy fix from 20260830_001 — Strava-parity).
--  13. The caller's own row in the leaderboard carries their actual
--      gender + age (not redacted from self — the user sees their
--      own placement clearly).
--  14. Filter parameters still operate on the underlying demographic
--      columns even though the returned gender/age are masked, so the
--      cohort filter remains correct.
--  15. Calling with auth.uid() = null (no JWT claim) raises 42501.
--
-- Reads as authenticated callers via `set local "request.jwt.claims"`.
-- No service-role bypass.

begin;

select plan(16);

-- ── Fixture: three runners with distinct demographics ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000cc0001', 'authenticated', 'authenticated',
   'route-owner@tiered.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000cc0002', 'authenticated', 'authenticated',
   'male-35@tiered.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000cc0003', 'authenticated', 'authenticated',
   'female-50@tiered.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000cc0004', 'authenticated', 'authenticated',
   'nonbinary-80@tiered.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000cc0005', 'authenticated', 'authenticated',
   'no-demographics@tiered.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000cc0099', 'authenticated', 'authenticated',
   'stranger@tiered.local', '', now(), now());

-- Five profiles with gender + DOB set (one left blank to exercise
-- the "no demographics → invisible to filtered queries" branch).
-- DOBs are picked so current age (vs now()) lands inside an obvious
-- 5-year bin: 35-39, 50-54, 75+ (80yo), null.
insert into user_profiles (id, display_name, gender, date_of_birth)
values
  ('00000000-0000-0000-0000-000000cc0001', 'Route Owner', 'male', '1985-01-01'),
  ('00000000-0000-0000-0000-000000cc0002', 'Male 35yo', 'male', (now() - interval '36 years')::date),
  ('00000000-0000-0000-0000-000000cc0003', 'Female 50yo', 'female', (now() - interval '51 years')::date),
  ('00000000-0000-0000-0000-000000cc0004', 'NB 80yo', 'nonbinary', (now() - interval '80 years')::date),
  ('00000000-0000-0000-0000-000000cc0005', 'No Demographics', null, null);

-- Route owner (cc0001) creates a public route + a private route.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000cc0001"}';
insert into routes (id, user_id, name, waypoints, distance_m, is_public)
values
  ('66666666-6666-6666-6666-666666660001',
   '00000000-0000-0000-0000-000000cc0001',
   'Public Tiered Loop',
   '[{"lat":47.37,"lng":8.54},{"lat":47.38,"lng":8.55}]',
   10000, true),
  ('66666666-6666-6666-6666-666666660002',
   '00000000-0000-0000-0000-000000cc0001',
   'Private Loop',
   '[{"lat":47.37,"lng":8.54},{"lat":47.38,"lng":8.55}]',
   10000, false);

insert into segments (id, route_id, name, start_distance_m, end_distance_m, author_id)
values
  ('77777777-7777-7777-7777-777777770001',
   '66666666-6666-6666-6666-666666660001',
   'Public Sprint',
   500, 1500,
   '00000000-0000-0000-0000-000000cc0001'),
  ('77777777-7777-7777-7777-777777770002',
   '66666666-6666-6666-6666-666666660002',
   'Private Sprint',
   500, 1500,
   '00000000-0000-0000-0000-000000cc0001');

-- Each runner records a run on the public route + plants one effort.
-- Times are picked so the leaderboard order is deterministic and we
-- exercise a tie (male-35 + female-50 both at 200s). Runs RLS requires
-- `auth.uid() = user_id` on insert, so we switch the JWT per row.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000cc0002"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('88888888-8888-8888-8888-888888880001',
   '00000000-0000-0000-0000-000000cc0002', now(), 10000, 1800, 'app', '{"activity_type":"run"}'::jsonb, true);

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000cc0003"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('88888888-8888-8888-8888-888888880002',
   '00000000-0000-0000-0000-000000cc0003', now(), 10000, 1900, 'app', '{"activity_type":"run"}'::jsonb, true);

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000cc0004"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('88888888-8888-8888-8888-888888880003',
   '00000000-0000-0000-0000-000000cc0004', now(), 10000, 2400, 'app', '{"activity_type":"run"}'::jsonb, true);

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000cc0005"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('88888888-8888-8888-8888-888888880004',
   '00000000-0000-0000-0000-000000cc0005', now(), 10000, 2100, 'app', '{"activity_type":"run"}'::jsonb, true);

-- segment_efforts insert RLS requires auth.uid() = user_id and
-- run-ownership match. One insert per user with a matching JWT.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000cc0002"}';
insert into segment_efforts (segment_id, run_id, user_id, time_seconds, started_at)
values ('77777777-7777-7777-7777-777777770001',
   '88888888-8888-8888-8888-888888880001',
   '00000000-0000-0000-0000-000000cc0002', 200, now() - interval '4 hours');

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000cc0003"}';
insert into segment_efforts (segment_id, run_id, user_id, time_seconds, started_at)
values ('77777777-7777-7777-7777-777777770001',
   '88888888-8888-8888-8888-888888880002',
   '00000000-0000-0000-0000-000000cc0003', 200, now() - interval '3 hours');

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000cc0004"}';
insert into segment_efforts (segment_id, run_id, user_id, time_seconds, started_at)
values ('77777777-7777-7777-7777-777777770001',
   '88888888-8888-8888-8888-888888880003',
   '00000000-0000-0000-0000-000000cc0004', 300, now() - interval '2 hours');

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000cc0005"}';
insert into segment_efforts (segment_id, run_id, user_id, time_seconds, started_at)
values ('77777777-7777-7777-7777-777777770001',
   '88888888-8888-8888-8888-888888880004',
   '00000000-0000-0000-0000-000000cc0005', 250, now() - interval '1 hour');

-- ── Tests run as the male-35yo viewer unless overridden. ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000cc0002"}';

-- 1. Unfiltered returns all four efforts.
select is(
  (select count(*)::int from segment_leaderboard_tiered(
     '77777777-7777-7777-7777-777777770001'::uuid, null, null, 50)),
  4,
  'unfiltered call returns every effort on the public segment'
);

-- 2. Order is time_seconds asc then started_at asc. The earlier-started
--    of the two 200s efforts (male-35, started -4h) comes before
--    female-50 (started -3h); the no-demographics 250s is third;
--    NB-80 at 300s is fourth.
select results_eq(
  $$ select user_id::text from segment_leaderboard_tiered(
       '77777777-7777-7777-7777-777777770001'::uuid, null, null, 50) $$,
  $$ values
       ('00000000-0000-0000-0000-000000cc0002'),
       ('00000000-0000-0000-0000-000000cc0003'),
       ('00000000-0000-0000-0000-000000cc0005'),
       ('00000000-0000-0000-0000-000000cc0004')
  $$,
  'ordering is time asc, started_at asc for ties'
);

-- 3. Gender filter narrows to male only.
select results_eq(
  $$ select user_id::text from segment_leaderboard_tiered(
       '77777777-7777-7777-7777-777777770001'::uuid, 'male', null, 50) $$,
  $$ values ('00000000-0000-0000-0000-000000cc0002') $$,
  'gender=male returns only male-identified profiles'
);

-- 4. Age-band filter narrows by current age. 35-39 should match the
--    male-35yo only — the female-50yo and the NB-80yo fall outside.
select results_eq(
  $$ select user_id::text from segment_leaderboard_tiered(
       '77777777-7777-7777-7777-777777770001'::uuid, null, '35-39', 50) $$,
  $$ values ('00000000-0000-0000-0000-000000cc0002') $$,
  'age_band=35-39 returns only the 35-39yo runner'
);

-- 5. '75+' is inclusive — the 80yo NB should appear.
select results_eq(
  $$ select user_id::text from segment_leaderboard_tiered(
       '77777777-7777-7777-7777-777777770001'::uuid, null, '75+', 50) $$,
  $$ values ('00000000-0000-0000-0000-000000cc0004') $$,
  '75+ band includes the 80yo runner'
);

-- 6. Combined filter — male + 35-39 → just male-35.
select results_eq(
  $$ select user_id::text from segment_leaderboard_tiered(
       '77777777-7777-7777-7777-777777770001'::uuid, 'male', '35-39', 50) $$,
  $$ values ('00000000-0000-0000-0000-000000cc0002') $$,
  'gender + age_band filter intersects'
);

-- 7. Filter with no matches returns zero rows (not an error).
select is(
  (select count(*)::int from segment_leaderboard_tiered(
     '77777777-7777-7777-7777-777777770001'::uuid, 'female', '35-39', 50)),
  0,
  'unsatisfiable filter returns zero rows'
);

-- 8. Runners with no demographics fall outside every filtered query
--    but still appear in the unfiltered baseline.
select is(
  (select count(*)::int from segment_leaderboard_tiered(
     '77777777-7777-7777-7777-777777770001'::uuid, null, '30-34', 50)),
  0,
  'no-demographics runner is invisible to age-band filters'
);

-- 9. A stranger calling against the public segment sees the
--    leaderboard. With the SECURITY DEFINER fix, the visibility filter
--    is replicated inside the function body — the cohort is reachable
--    on a public route regardless of who the caller is.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000cc0099"}';
select is(
  (select count(*)::int from segment_leaderboard_tiered(
     '77777777-7777-7777-7777-777777770001'::uuid, null, null, 50)),
  4,
  'stranger can read the leaderboard on a public route'
);

-- 10. Same stranger against the PRIVATE segment sees zero rows. With
--     SECURITY DEFINER the function bypasses RLS, so this test pins
--     the manually-replicated visibility filter (routes.is_public OR
--     auth.uid()=user_id OR is_club_member). A regression that dropped
--     the filter would surface here.
select is(
  (select count(*)::int from segment_leaderboard_tiered(
     '77777777-7777-7777-7777-777777770002'::uuid, null, null, 50)),
  0,
  'stranger sees zero rows on a private-route segment'
);

-- 11. Malformed age band raises 22023 (data_exception).
select throws_ok(
  $$ select * from segment_leaderboard_tiered(
       '77777777-7777-7777-7777-777777770001'::uuid, null, 'eighty-plus', 50) $$,
  '22023',
  null,
  'malformed p_age_band raises data_exception (22023)'
);

-- ── Privacy posture: cross-user demographics are masked. ──
-- Stranger (cc0099) reads the public-segment leaderboard. None of the
-- four returned rows are theirs, so every gender and age should be
-- NULL — the 20260830_001 fix's load-bearing invariant.
select is(
  (select count(*)::int
     from segment_leaderboard_tiered(
       '77777777-7777-7777-7777-777777770001'::uuid, null, null, 50)
     where gender is not null or age is not null),
  0,
  'cross-user rows in the leaderboard have NULL gender + age'
);

-- 13. The caller's own row carries their gender + age (not masked
--     from self — the user sees their own placement clearly).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000cc0002"}';
select is(
  (select gender from segment_leaderboard_tiered(
     '77777777-7777-7777-7777-777777770001'::uuid, null, null, 50)
   where user_id = '00000000-0000-0000-0000-000000cc0002'),
  'male'::text,
  'self-row gender is visible to the calling user'
);
select cmp_ok(
  (select age from segment_leaderboard_tiered(
     '77777777-7777-7777-7777-777777770001'::uuid, null, null, 50)
   where user_id = '00000000-0000-0000-0000-000000cc0002'),
  '>=', 35,
  'self-row age is at least 35 (the male-35yo fixture aged 36 since insert)'
);

-- 14. Filter parameters still operate on the underlying demographic
--     columns even though the returned gender/age are masked. As the
--     stranger (cc0099) filter for gender=female + age 50-54 must
--     return only the female-50 row, proving the filter applied to
--     up.gender / up.date_of_birth, not the masked return column.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000cc0099"}';
select results_eq(
  $$ select user_id::text from segment_leaderboard_tiered(
       '77777777-7777-7777-7777-777777770001'::uuid, 'female', '50-54', 50) $$,
  $$ values ('00000000-0000-0000-0000-000000cc0003') $$,
  'demographic filter operates on underlying columns, not the masked return columns'
);

-- 15. auth.uid() = null callers are rejected with 42501. The pgtap
--     session reverts to no-JWT via setting an empty claims object.
set local "request.jwt.claims" = '{}';
select throws_ok(
  $$ select * from segment_leaderboard_tiered(
       '77777777-7777-7777-7777-777777770001'::uuid, null, null, 50) $$,
  '42501',
  null,
  'caller with null auth.uid() is rejected with 42501'
);

select * from finish();
rollback;
