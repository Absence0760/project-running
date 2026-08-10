-- Pins migration 20270514_001: a bike ride cannot hold a running PR.
--
-- `refresh_personal_records_for_user` filtered on `source` and `is_dnf` but
-- never on `activity_type`, so a 5 km ride at 9:00 replaced the runner's
-- genuine 25:00 5K in the `personal_records` cache — and, through `v_pr_count`,
-- fed the PR badge family too. The client's recap engine has always gated
-- "longest"/"fastest" on `isRunFamily = activity_type !== 'cycle'` while
-- keeping totals cross-modal; this suite pins the cache to the same rule.
--
--   1. A faster cycle effort does not take the PR from a slower run.
--   2. A cycle-only runner holds no PRs at all.
--   3. walk / hike / stroller still count — only `cycle` leaves the family.
--   4. Embedded-best columns on a cycle row are excluded too.
--   5. The UPDATE trigger watches `activity_type`: re-typing a run to `cycle`
--      (and back) re-derives the cache instead of leaving it stale.
--   6. The single-run distance badge is run-family, lifetime distance is not.

begin;

select plan(8);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000fa001', 'authenticated', 'authenticated',
   'runner@prf.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000fb002', 'authenticated', 'authenticated',
   'cyclist@prf.local', '', now(), now());

insert into user_profiles (id, display_name)
values
  ('00000000-0000-0000-0000-0000000fa001', 'Runner'),
  ('00000000-0000-0000-0000-0000000fb002', 'Cyclist');

select tests.confirm_consent();

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000fa001"}';

-- A genuine 5K run at 25:00, then a 5 km ride at 9:00 and a 5 km walk at 55:00.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, activity_type, metadata)
values
  ('c1c1c1c1-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000fa001',
   now() - interval '3 days', 5000, 1500, 'app', 'run',
   '{"activity_type":"run"}'::jsonb),
  ('c1c1c1c1-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000fa001',
   now() - interval '2 days', 5000, 540, 'app', 'cycle',
   '{"activity_type":"cycle"}'::jsonb);

-- 1. The run keeps the 5K PR; the faster ride is not a candidate.
select results_eq(
  $$ select best_time_s, run_id::text from personal_records
     where user_id = '00000000-0000-0000-0000-0000000fa001' and distance = '5k' $$,
  $$ values (1500, 'c1c1c1c1-0000-0000-0000-0000000000e1') $$,
  'a faster bike ride does not take the 5K PR from the slower run'
);

-- 2. A 10 km ride on its own earns no PR at all.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000fb002"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, activity_type, metadata)
values ('c1c1c1c1-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000fb002',
        now() - interval '1 day', 10000, 1080, 'app', 'cycle',
        '{"activity_type":"cycle"}'::jsonb);
select is_empty(
  $$ select distance from personal_records
     where user_id = '00000000-0000-0000-0000-0000000fb002' $$,
  'a cycle-only athlete holds no running personal records'
);

-- 3. Only `cycle` leaves the run family — a 10 km walk still sets a 10K PR.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000fa001"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, activity_type, metadata)
values ('c1c1c1c1-0000-0000-0000-0000000000e4', '00000000-0000-0000-0000-0000000fa001',
        now() - interval '1 day', 10000, 6000, 'app', 'walk',
        '{"activity_type":"walk"}'::jsonb);
select results_eq(
  $$ select best_time_s from personal_records
     where user_id = '00000000-0000-0000-0000-0000000fa001' and distance = '10k' $$,
  $$ values (6000) $$,
  'walk / hike / stroller stay in the run family — only cycle is excluded'
);

-- 4. The embedded-best columns on a cycle row are excluded too: a ride whose
--    fastest 5 km split is 8:00 must not become the 5K PR either.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, activity_type,
                  fastest_5k_s, metadata)
values ('c1c1c1c1-0000-0000-0000-0000000000e5', '00000000-0000-0000-0000-0000000fa001',
        now() - interval '12 hours', 40000, 4200, 'app', 'cycle', 480,
        '{"activity_type":"cycle"}'::jsonb);
select results_eq(
  $$ select best_time_s from personal_records
     where user_id = '00000000-0000-0000-0000-0000000fa001' and distance = '5k' $$,
  $$ values (1500) $$,
  'an embedded 5k split inside a bike ride is not a 5K PR'
);

-- 5. The UPDATE watch list includes activity_type — re-typing the ride to a run
--    must re-derive the cache, and re-typing it back must give the PR back.
update runs set activity_type = 'run', metadata = '{"activity_type":"run"}'::jsonb
where id = 'c1c1c1c1-0000-0000-0000-0000000000e2';
select results_eq(
  $$ select best_time_s from personal_records
     where user_id = '00000000-0000-0000-0000-0000000fa001' and distance = '5k' $$,
  $$ values (540) $$,
  'flipping cycle -> run refreshes the cache (the trigger watches activity_type)'
);
update runs set activity_type = 'cycle', metadata = '{"activity_type":"cycle"}'::jsonb
where id = 'c1c1c1c1-0000-0000-0000-0000000000e2';
select results_eq(
  $$ select best_time_s from personal_records
     where user_id = '00000000-0000-0000-0000-0000000fa001' and distance = '5k' $$,
  $$ values (1500) $$,
  'flipping run -> cycle refreshes the cache back'
);

-- 6. Achievements: the single-run distance badge is run-family (a 100 km ride
--    does not earn the 50 km platinum tier), lifetime distance is cross-modal
--    (10 km ridden earlier + 100 km here clears the 100 km bronze threshold).
set local role postgres;
insert into runs (id, user_id, started_at, distance_m, duration_s, source, activity_type, metadata)
values ('c1c1c1c1-0000-0000-0000-0000000000e6', '00000000-0000-0000-0000-0000000fb002',
        now(), 100000, 14400, 'app', 'cycle', '{"activity_type":"cycle"}'::jsonb);
select is_empty(
  $$ select tier from achievements
     where user_id = '00000000-0000-0000-0000-0000000fb002'
       and badge_key = 'distance_single' $$,
  'a 100 km bike ride earns no single-RUN distance badge'
);
select results_eq(
  $$ select tier from achievements
     where user_id = '00000000-0000-0000-0000-0000000fb002'
       and badge_key = 'distance_lifetime' $$,
  $$ values ('bronze'::text) $$,
  'lifetime distance stays cross-modal — the ride counts toward the total'
);

select * from finish();
rollback;
