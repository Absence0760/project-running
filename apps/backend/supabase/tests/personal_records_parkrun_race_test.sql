-- Pins migration 20270421_001 — parkrun + race runs are PR-eligible (#378).
--
-- Before the fix, refresh_personal_records_for_user filtered
--   source in ('app','watch','strava','garmin','healthkit','healthconnect')
-- so a fastest-5K run at parkrun and a marathon run as a chip-timed 'race'
-- never produced a personal_records row. Both are valid runs.source values.

begin;
select plan(4);

do $$
declare
  v_user uuid := '88888888-8888-8888-8888-8888aaaa0378';
begin
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values (v_user, 'pr-parkrun-race@example.com', '',
            now(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated')
    on conflict (id) do nothing;
end $$;

-- A parkrun 5K (source 'parkrun') and an official marathon (source 'race').
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata)
values
  ('c0000378-0000-0000-0000-000000005000',
   '88888888-8888-8888-8888-8888aaaa0378',
   '2026-05-02 09:00:00+00', 5000, 1200, 'parkrun', '{"activity_type":"run"}'),
  ('c0000378-0000-0000-0000-000000042195',
   '88888888-8888-8888-8888-8888aaaa0378',
   '2026-06-01 09:00:00+00', 42195, 14400, 'race', '{"activity_type":"run"}');

do $$
begin
  perform refresh_personal_records_for_user(
    '88888888-8888-8888-8888-8888aaaa0378'::uuid
  );
end $$;

select is(
  (select count(*) from personal_records
   where user_id = '88888888-8888-8888-8888-8888aaaa0378'
     and distance = '5k'),
  1::bigint,
  'a parkrun 5K produces a 5k PR row'
);

select is(
  (select run_id from personal_records
   where user_id = '88888888-8888-8888-8888-8888aaaa0378'
     and distance = '5k'),
  'c0000378-0000-0000-0000-000000005000'::uuid,
  'the 5k PR points at the parkrun run'
);

select is(
  (select count(*) from personal_records
   where user_id = '88888888-8888-8888-8888-8888aaaa0378'
     and distance = 'marathon'),
  1::bigint,
  'a race marathon produces a marathon PR row'
);

select is(
  (select run_id from personal_records
   where user_id = '88888888-8888-8888-8888-8888aaaa0378'
     and distance = 'marathon'),
  'c0000378-0000-0000-0000-000000042195'::uuid,
  'the marathon PR points at the chip-timed race run'
);

rollback;
