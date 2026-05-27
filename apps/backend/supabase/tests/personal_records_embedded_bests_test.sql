-- Pins migration 20260529_001 — personal-records also reads embedded
-- best efforts from `metadata.fastest_X_s`. Persona-hunt Round 2 #4.
--
-- Scenario: a pro runs an 18 km tempo with a sub-20 5k embedded in
-- the middle. The whole-run distance_m=18000 doesn't fit any
-- canonical bracket, so pre-fix the trigger missed the 5k effort
-- entirely. Post-fix the mobile client writes the embedded best to
-- `metadata.fastest_5k_s` and the trigger picks it up.

begin;
select plan(5);

do $$
declare
  v_user uuid := '99999999-9999-9999-9999-99999999ffff';
begin
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values (v_user, 'embedded-pr@example.com', '',
            now(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated')
    on conflict (id) do nothing;
end $$;

-- An 18 km tempo with an embedded sub-20 5k. The whole-run time is
-- 80 min; the middle 5k clocked 19:30 (1170s).
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata)
values (
  '11111111-1111-1111-1111-111111111111',
  '99999999-9999-9999-9999-99999999ffff',
  '2026-04-01 09:00:00+00',
  18000,
  4800,
  'app',
  jsonb_build_object('fastest_5k_s', 1170)
);

-- A separate 5k race finish at 19:45 (whole-run). Slightly slower
-- than the embedded effort above — the trigger should pick the
-- embedded as the PR.
insert into runs (id, user_id, started_at, distance_m, duration_s, source)
values (
  '22222222-2222-2222-2222-222222222222',
  '99999999-9999-9999-9999-99999999ffff',
  '2026-04-08 09:00:00+00',
  5000,
  1185,
  'app'
);

-- Trigger explicit refresh.
do $$
begin
  perform refresh_personal_records_for_user(
    '99999999-9999-9999-9999-99999999ffff'::uuid
  );
end $$;

select is(
  (select count(*) from personal_records
   where user_id = '99999999-9999-9999-9999-99999999ffff'
     and distance = '5k'),
  1::bigint,
  'Exactly one 5k PR (best of whole-run and embedded)'
);

select is(
  (select best_time_s from personal_records
   where user_id = '99999999-9999-9999-9999-99999999ffff'
     and distance = '5k'),
  1170,
  'PR is the embedded 19:30 (1170s), not the whole-run 5k race (1185s)'
);

select is(
  (select run_id from personal_records
   where user_id = '99999999-9999-9999-9999-99999999ffff'
     and distance = '5k'),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'PR points at the long run (where the embedded effort lived)'
);

-- An empty / missing metadata.fastest_X_s must NOT crash the trigger
-- and must NOT promote a 0 / null candidate to PR.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata)
values (
  '33333333-3333-3333-3333-333333333333',
  '99999999-9999-9999-9999-99999999ffff',
  '2026-04-15 09:00:00+00',
  3000,
  900,
  'app',
  jsonb_build_object('fastest_5k_s', 'nope')  -- non-numeric — must be skipped
);

do $$
begin
  perform refresh_personal_records_for_user(
    '99999999-9999-9999-9999-99999999ffff'::uuid
  );
end $$;

select is(
  (select best_time_s from personal_records
   where user_id = '99999999-9999-9999-9999-99999999ffff'
     and distance = '5k'),
  1170,
  'Non-numeric metadata.fastest_5k_s value is skipped, PR unchanged'
);

-- Boundary: a 10k whole-run that fits the bracket beats an embedded
-- 10k from a different run that's slower.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata)
values (
  '44444444-4444-4444-4444-444444444444',
  '99999999-9999-9999-9999-99999999ffff',
  '2026-04-22 09:00:00+00',
  10000,
  2400,
  'app'
),
(
  '55555555-5555-5555-5555-555555555555',
  '99999999-9999-9999-9999-99999999ffff',
  '2026-04-29 09:00:00+00',
  25000,
  6000,
  'app',
  jsonb_build_object('fastest_10k_s', 2450)
);

do $$
begin
  perform refresh_personal_records_for_user(
    '99999999-9999-9999-9999-99999999ffff'::uuid
  );
end $$;

select is(
  (select best_time_s from personal_records
   where user_id = '99999999-9999-9999-9999-99999999ffff'
     and distance = '10k'),
  2400,
  'Whole-run 10k (40min) beats embedded 10k (40:50) — trigger picks min across both kinds'
);

rollback;
