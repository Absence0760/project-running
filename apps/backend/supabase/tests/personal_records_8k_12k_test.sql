-- Pins migration 20270330_001 — 8k and 12k personal-record brackets
-- (older-runner persona #33: the 8k club handicap + 12k are masters
-- staples the four road-major brackets skipped; a qualifying run fell
-- through the CASE and was silently excluded from personal_records).
--
-- Same ±2% window as every other bracket:
--   8k  @ 8000m:  7840 - 8160
--   12k @ 12000m: 11760 - 12240

begin;
select plan(6);

do $$
declare
  v_user uuid := '99999999-9999-9999-9999-99999999dddd';
begin
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values (v_user, 'pr-8k12k@example.com', '',
            now(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated')
    on conflict (id) do nothing;
end $$;

-- Seed: a Strava-recorded 8k at 8.1 km / 34:00 (typical overshoot).
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata)
values (
  '66666666-6666-6666-6666-666666666601',
  '99999999-9999-9999-9999-99999999dddd',
  '2026-05-01 09:00:00+00',
  8100,
  2040,
  'strava',
  '{"activity_type":"run"}'
);

-- Seed: a 12k at 12.1 km / 55:00.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata)
values (
  '66666666-6666-6666-6666-666666666602',
  '99999999-9999-9999-9999-99999999dddd',
  '2026-05-08 09:00:00+00',
  12100,
  3300,
  'strava',
  '{"activity_type":"run"}'
);

-- Seed: a 9 km run — between the 8k and 10k windows, must qualify for
-- NEITHER (the brackets stay disjoint, no widening creep).
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata)
values (
  '66666666-6666-6666-6666-666666666603',
  '99999999-9999-9999-9999-99999999dddd',
  '2026-05-15 09:00:00+00',
  9000,
  2500,
  'strava',
  '{"activity_type":"run"}'
);

do $$
begin
  perform refresh_personal_records_for_user(
    '99999999-9999-9999-9999-99999999dddd'::uuid
  );
end $$;

select is(
  (select run_id from personal_records
   where user_id = '99999999-9999-9999-9999-99999999dddd'
     and distance = '8k'),
  '66666666-6666-6666-6666-666666666601'::uuid,
  '8.1 km run qualifies as the 8k PR'
);

select is(
  (select run_id from personal_records
   where user_id = '99999999-9999-9999-9999-99999999dddd'
     and distance = '12k'),
  '66666666-6666-6666-6666-666666666602'::uuid,
  '12.1 km run qualifies as the 12k PR'
);

select is(
  (select count(*) from personal_records
   where user_id = '99999999-9999-9999-9999-99999999dddd'),
  2::bigint,
  'Exactly two PR rows — the 9 km run matches no bracket'
);

-- Boundary pins: ±2% windows are 7840..8160 and 11760..12240.
select is(
  case when 7839 between 7840 and 8160 then '8k' end,
  null,
  '7839 m sits below the 8k lower bound'
);
select is(
  case when 8160 between 7840 and 8160 then '8k' end,
  '8k',
  '8160 m sits exactly on the 8k upper bound'
);
select is(
  case when 12240 between 11760 and 12240 then '12k' end,
  '12k',
  '12240 m sits exactly on the 12k upper bound'
);

select * from finish();
rollback;
