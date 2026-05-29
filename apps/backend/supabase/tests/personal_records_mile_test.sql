-- Pins migration 20261021_001 — the 1-mile (1609 m) PR bracket
-- (older-runner persona #31). Asserts a ~1-mile run produces a '1_mile'
-- personal_records row, the widened CHECK admits the value, and a clearly
-- shorter (1500 m) run does NOT shadow the mile bracket.

begin;
select plan(3);

insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                        instance_id, aud, role)
  values ('99999999-9999-9999-9999-999900000a01',
          'pr-mile@example.com', '', now(),
          '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
  on conflict (id) do nothing;

-- A 1609 m run at 6:00. Should land as the 1_mile PR.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata)
values ('aaaaaaaa-0000-0000-0000-0000000000a1',
        '99999999-9999-9999-9999-999900000a01',
        '2026-04-01 09:00:00+00', 1609, 360, 'app', '{"activity_type":"run"}');

-- A 1500 m run (below the 1559 floor) — must NOT count as a mile.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata)
values ('bbbbbbbb-0000-0000-0000-0000000000b2',
        '99999999-9999-9999-9999-999900000a01',
        '2026-04-02 09:00:00+00', 1500, 320, 'app', '{"activity_type":"run"}');

select refresh_personal_records_for_user('99999999-9999-9999-9999-999900000a01');

select is(
  (select best_time_s from personal_records
   where user_id = '99999999-9999-9999-9999-999900000a01' and distance = '1_mile'),
  360,
  'a 1609 m run becomes the 1_mile PR');

select is(
  (select run_id from personal_records
   where user_id = '99999999-9999-9999-9999-999900000a01' and distance = '1_mile'),
  'aaaaaaaa-0000-0000-0000-0000000000a1'::uuid,
  'the 1_mile PR points at the 1609 m run, not the 1500 m run');

select is(
  (select count(*)::int from personal_records
   where user_id = '99999999-9999-9999-9999-999900000a01'),
  1,
  'only the mile bracket matched — the 1500 m run produced no PR row');

select * from finish();
rollback;
