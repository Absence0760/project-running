-- Every personal-record candidate time is positive (migration 20270706000003).
--
-- Two claims, and the first is the reachable one: a zero-second run in a PR
-- bracket used to be the FASTEST candidate for that bracket, reach
-- `personal_records`, and be refused there by `best_time_s > 0` -- from inside
-- an AFTER trigger on `runs`, so the 23514 failed the INSERT of the run. The
-- runner could not save the activity, and the error named a table with no
-- relation to anything they had done.
--
-- The second is the filed one: the four embedded-best branches read `>= 0`,
-- which `20270705000004`'s column CHECKs had made equivalent rather than
-- load-bearing. Equivalent is not the same as unreachable, so it is pinned from
-- the only side a test can reach it -- as service_role, past the CHECK the
-- clients hit, which is exactly the position a bad backfill or a future column
-- widening would be in.

begin;

select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000e0001'::uuid, 'authenticated', 'authenticated',
        'zerotime@pr.local', '', now(), now());

insert into user_profiles (id, display_name)
values ('00000000-0000-0000-0000-0000000e0001', 'Zero Time');

select tests.confirm_consent();

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000e0001"}';

-- 1. The run saves. Before this migration the INSERT raised 23514 from
--    personal_records_best_time_s_check, inside trigger_refresh_personal_records.
select lives_ok(
  $$insert into runs (id, user_id, started_at, duration_s, distance_m, source)
    values ('00000000-0000-0000-0000-0000000e1001',
            '00000000-0000-0000-0000-0000000e0001', now() - interval '3 days',
            0, 5000, 'app')$$,
  'a zero-second run in a PR bracket can be saved'
);

-- 2. And sets nothing. `order by duration_s asc` makes zero the fastest
--    candidate there is, so a filter that let it through would hand every
--    bracket it touches a 0:00 record.
select is(
  (select count(*)::int from personal_records
   where user_id = '00000000-0000-0000-0000-0000000e0001'),
  0,
  'a zero-second run sets no personal record'
);

-- 3. The positive control: a real 5k does, so 2 cannot be passing because
--    nothing reaches the table.
insert into runs (id, user_id, started_at, duration_s, distance_m, source)
values ('00000000-0000-0000-0000-0000000e1002',
        '00000000-0000-0000-0000-0000000e0001', now() - interval '2 days',
        1200, 5000, 'app');

select is(
  (select best_time_s from personal_records
   where user_id = '00000000-0000-0000-0000-0000000e0001' and distance = '5k'),
  1200,
  'a genuine 5k still sets the record'
);

-- 4. And the zero-second run did not displace it, which is what the ranking
--    would have done had the candidate survived.
select is(
  (select run_id from personal_records
   where user_id = '00000000-0000-0000-0000-0000000e0001' and distance = '5k'),
  '00000000-0000-0000-0000-0000000e1002'::uuid,
  'the record is the run that was actually run'
);

-- 5. The embedded-best half. `runs_fastest_10k_s_check` refuses a zero from an
--    ordinary session, so the only way to put one in front of the refresher is
--    the position a backfill or a widened column would occupy: past the CHECK.
--    The branch that reads it must not award it either.
reset role;
alter table runs drop constraint runs_fastest_10k_s_check;
insert into runs (id, user_id, started_at, duration_s, distance_m, source, fastest_10k_s)
values ('00000000-0000-0000-0000-0000000e1003',
        '00000000-0000-0000-0000-0000000e0001', now() - interval '1 day',
        7200, 18000, 'app', 0);
select refresh_personal_records_for_user('00000000-0000-0000-0000-0000000e0001');

select is(
  (select count(*)::int from personal_records
   where user_id = '00000000-0000-0000-0000-0000000e0001' and distance = '10k'),
  0,
  'a zero-second embedded best sets no personal record'
);

-- 6. The positive control for 5, on the same run and the same branch.
update runs set fastest_10k_s = 2400
 where id = '00000000-0000-0000-0000-0000000e1003';
select refresh_personal_records_for_user('00000000-0000-0000-0000-0000000e0001');

select is(
  (select best_time_s from personal_records
   where user_id = '00000000-0000-0000-0000-0000000e0001' and distance = '10k'),
  2400,
  'a positive embedded best still sets the record'
);

select * from finish();
rollback;
