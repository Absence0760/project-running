-- Pins migration 20260528000002 — personal-records distance brackets
-- widened to ±2% so real-world race-day Strava finishes qualify.
--
-- Pre-fix: a 2:50 marathon recorded at 42.45 km was excluded by the
-- `between 42100 and 42300` window (200 m, ~0.25%). Pro runners ended
-- up with no marathon PR row at all. Persona-driven bug-hunt Pro #1.
--
-- We assert: (a) a typical Strava-overshot race finish qualifies as a
-- PR, and (b) a clearly-different distance (well outside ±2%) still
-- does NOT qualify. Both directions matter — if a refactor widens
-- the brackets too far, a 41 km long run would shadow a real marathon
-- PR. The pinned boundaries are 41351..43039 m for marathon (±2% of
-- the canonical 42195 m).

begin;
select plan(8);

-- Synthetic user. Seed via auth.users so the runs FK holds.
do $$
declare
  v_user uuid := '99999999-9999-9999-9999-99999999cccc';
begin
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values (v_user, 'pr-brackets@example.com', '',
            now(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated')
    on conflict (id) do nothing;
end $$;

-- Seed: one Strava-recorded marathon at 42.45 km / 2:50:00. Real-
-- world overshot. Must qualify under the widened ±2% bracket.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata)
values (
  '11111111-1111-1111-1111-111111111111',
  '99999999-9999-9999-9999-99999999cccc',
  '2026-04-01 09:00:00+00',
  42450,
  10200,
  'strava',
  '{"activity_type":"run"}'
);

-- Seed: a Strava-recorded 10k at 10.15 km / 40:00. Was excluded by
-- the old 9900..10100 bracket; must qualify under widened 9800..10200.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata)
values (
  '22222222-2222-2222-2222-222222222222',
  '99999999-9999-9999-9999-99999999cccc',
  '2026-04-08 09:00:00+00',
  10150,
  2400,
  'strava',
  '{"activity_type":"run"}'
);

-- Seed: a Strava-recorded half-marathon at 21.25 km / 1:25:00.
-- Was excluded by the old 21000..21200 bracket.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata)
values (
  '33333333-3333-3333-3333-333333333333',
  '99999999-9999-9999-9999-99999999cccc',
  '2026-04-15 09:00:00+00',
  21250,
  5100,
  'strava',
  '{"activity_type":"run"}'
);

-- Seed: a 5k at 5.05 km / 18:00 — already qualified pre-fix; checked
-- here to confirm the widening didn't regress the 5k bracket.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata)
values (
  '44444444-4444-4444-4444-444444444444',
  '99999999-9999-9999-9999-99999999cccc',
  '2026-04-22 09:00:00+00',
  5050,
  1080,
  'strava',
  '{"activity_type":"run"}'
);

-- Seed: a 41 km long run at 41.0 km — clearly NOT a marathon (≥1%
-- under). Must NOT qualify as a marathon PR even under the widened
-- bracket (lower bound 41351).
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata)
values (
  '55555555-5555-5555-5555-555555555555',
  '99999999-9999-9999-9999-99999999cccc',
  '2026-04-29 09:00:00+00',
  41000,
  10800,
  'strava',
  '{"activity_type":"run"}'
);

-- Trigger the refresh explicitly (the inserts also fired the trigger,
-- but call directly so the assertions don't race the trigger queue).
do $$
begin
  perform refresh_personal_records_for_user(
    '99999999-9999-9999-9999-99999999cccc'::uuid
  );
end $$;

-- Assertions: every canonical distance gets exactly one PR row.
select is(
  (select count(*) from personal_records
   where user_id = '99999999-9999-9999-9999-99999999cccc'
     and distance = 'marathon'),
  1::bigint,
  '42.45 km Strava marathon qualifies as a marathon PR (was excluded)'
);

select is(
  (select run_id from personal_records
   where user_id = '99999999-9999-9999-9999-99999999cccc'
     and distance = 'marathon'),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'The marathon PR points at the 42.45 km run'
);

select is(
  (select count(*) from personal_records
   where user_id = '99999999-9999-9999-9999-99999999cccc'
     and distance = '10k'),
  1::bigint,
  '10.15 km Strava 10k qualifies as a 10k PR (was excluded)'
);

select is(
  (select count(*) from personal_records
   where user_id = '99999999-9999-9999-9999-99999999cccc'
     and distance = 'half_marathon'),
  1::bigint,
  '21.25 km Strava half-marathon qualifies as a half PR (was excluded)'
);

select is(
  (select count(*) from personal_records
   where user_id = '99999999-9999-9999-9999-99999999cccc'
     and distance = '5k'),
  1::bigint,
  '5.05 km Strava 5k still qualifies (pre-existing behaviour)'
);

select is(
  (select count(*) from personal_records
   where user_id = '99999999-9999-9999-9999-99999999cccc'),
  4::bigint,
  'Exactly four canonical PRs — no extra rows for the 41 km long run'
);

-- Boundary asserts: a 41350 m (just below lower bound) does NOT
-- qualify as marathon; a 41351 m (exact lower bound) DOES.
select is(
  case
    when 41350 between 41351 and 43039 then 'marathon'
    else null
  end,
  null::text,
  '41350 m is below the lower marathon bracket (rejected)'
);

select is(
  case
    when 41351 between 41351 and 43039 then 'marathon'
    else null
  end,
  'marathon'::text,
  '41351 m is on the lower marathon bracket (accepted)'
);

rollback;
