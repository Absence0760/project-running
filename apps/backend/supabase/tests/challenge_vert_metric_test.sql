-- Vert / elevation-gain challenge metric (migration 20270302_001).
-- Proves: the metadata.elevation_m backfill into runs.elevation_gain_m, the
-- vert leaderboard sum (null elevation contributes 0, not null), the vert
-- completion + badge path, and that elevation_gain_m passes through public_runs.

begin;

select plan(7);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000e0000001', 'authenticated', 'authenticated', 'a@ve.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000e0000002', 'authenticated', 'authenticated', 'b@ve.local', '', now(), now());

insert into user_profiles (id, display_name) values
  ('00000000-0000-0000-0000-0000e0000001', 'Vea'),
  ('00000000-0000-0000-0000-0000e0000002', 'Vob')
on conflict (id) do nothing;

-- ── backfill assertion: a run seeded WITHOUT elevation_gain_m but WITH the
-- metadata.elevation_m key gets the column populated by the migration's UPDATE.
-- The migration already ran at db-reset, so a row inserted here won't be
-- backfilled; instead assert the backfill expression directly by inserting a
-- row that mimics a pre-migration row and re-running the same expression.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, activity_type, metadata) values
  ('22222222-2222-2222-2222-2222e0000009', '00000000-0000-0000-0000-0000e0000001', '2026-06-01 06:00:00+00', 8000, 2400, 'strava', true, 'run', '{"activity_type":"run","elevation_m":640}');

update runs
set elevation_gain_m = (metadata->>'elevation_m')::numeric
where id = '22222222-2222-2222-2222-2222e0000009'
  and elevation_gain_m is null;

select is(
  (select elevation_gain_m::int from runs where id = '22222222-2222-2222-2222-2222e0000009'),
  640, 'backfill: metadata.elevation_m populates elevation_gain_m');

-- ── vert leaderboard: Vea climbs 640 (above) + 360 in-window = 1000; one
-- in-window run has NO elevation (null → contributes 0). Vob climbs 500.
-- An out-of-window 9000m climb must NOT count.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, activity_type, elevation_gain_m, metadata) values
  ('22222222-2222-2222-2222-2222e0000001', '00000000-0000-0000-0000-0000e0000001', '2026-06-08 06:00:00+00', 5000, 1800, 'app', true, 'run', 360, '{"activity_type":"run"}'),
  ('22222222-2222-2222-2222-2222e0000002', '00000000-0000-0000-0000-0000e0000001', '2026-06-09 06:00:00+00', 5000, 1800, 'app', true, 'run', null, '{"activity_type":"run"}'),
  ('22222222-2222-2222-2222-2222e0000003', '00000000-0000-0000-0000-0000e0000002', '2026-06-10 06:00:00+00', 5000, 1800, 'app', true, 'run', 500, '{"activity_type":"run"}'),
  ('22222222-2222-2222-2222-2222e0000004', '00000000-0000-0000-0000-0000e0000001', '2026-05-20 06:00:00+00', 5000, 1800, 'app', true, 'run', 9000, '{"activity_type":"run"}');

insert into challenges (id, creator_id, title, metric, scope, goal_value, starts_at, ends_at, is_public) values
  ('eeeeeeee-eeee-eeee-eeee-eeeee0000001', '00000000-0000-0000-0000-0000e0000001',
   'VE Vert', 'vert', 'individual', 1000,
   '2026-06-01 00:00:00+00', '2026-06-30 00:00:00+00', true);

insert into challenge_participants (challenge_id, user_id) values
  ('eeeeeeee-eeee-eeee-eeee-eeeee0000001', '00000000-0000-0000-0000-0000e0000001'),
  ('eeeeeeee-eeee-eeee-eeee-eeeee0000001', '00000000-0000-0000-0000-0000e0000002');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000e0000001"}';

select results_eq(
  $$ select user_id, value::int, rank::int
     from challenge_leaderboard('eeeeeeee-eeee-eeee-eeee-eeeee0000001', false)
     order by rank, user_id $$,
  $$ values
       ('00000000-0000-0000-0000-0000e0000001'::uuid, 1000, 1),
       ('00000000-0000-0000-0000-0000e0000002'::uuid, 500, 2) $$,
  'vert board: Vea 640+360=1000 (null run = 0), Vob 500, out-of-window excluded');

-- A run with a NULL elevation must not null the SUM (coalesce-0 inside the sum).
select isnt(
  (select value from challenge_leaderboard('eeeeeeee-eeee-eeee-eeee-eeeee0000001', false)
   where user_id = '00000000-0000-0000-0000-0000e0000001'),
  null, 'a null-elevation run does not null the vert sum');

-- ── completion: Vea (1000) meets goal_value 1000 → exactly one badge, idempotent.
reset role;
select recompute_challenge_completion('eeeeeeee-eeee-eeee-eeee-eeeee0000001', '00000000-0000-0000-0000-0000e0000001');
select recompute_challenge_completion('eeeeeeee-eeee-eeee-eeee-eeeee0000001', '00000000-0000-0000-0000-0000e0000001');

select is(
  (select count(*)::int from challenge_badges
   where challenge_id = 'eeeeeeee-eeee-eeee-eeee-eeeee0000001'
     and user_id = '00000000-0000-0000-0000-0000e0000001'),
  1, 'vert completion awards exactly one badge (idempotent)');

select is(
  (select final_value::int from challenge_badges
   where challenge_id = 'eeeeeeee-eeee-eeee-eeee-eeeee0000001'
     and user_id = '00000000-0000-0000-0000-0000e0000001'),
  1000, 'vert badge records the summed final_value');

-- Vob (500 < 1000 goal) earns no badge.
select is(
  (select count(*)::int from challenge_badges
   where challenge_id = 'eeeeeeee-eeee-eeee-eeee-eeeee0000001'
     and user_id = '00000000-0000-0000-0000-0000e0000002'),
  0, 'a participant short of goal earns no vert badge');

-- ── public_runs passes elevation_gain_m through ──
select is(
  (select elevation_gain_m::int from public_runs where id = '22222222-2222-2222-2222-2222e0000001'),
  360, 'elevation_gain_m passes through the public_runs view');

select * from finish();

rollback;
