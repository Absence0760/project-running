-- challenge_leaderboard aggregate (challenges.md; migration 20270210_001).
-- Proves the window filter, per-metric aggregate, deterministic ranking, the
-- activity_type filter, and the club_vs_club team grouping. The aggregate is
-- SECURITY INVOKER over `activities`, so a participant's contribution only
-- counts for a viewer who can see those runs — runs are seeded is_public so the
-- board is viewer-independent (the spec's opted-in-participants property).

begin;

select plan(7);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000cb000001', 'authenticated', 'authenticated', 'a@cb.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000cb000002', 'authenticated', 'authenticated', 'b@cb.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000cb000003', 'authenticated', 'authenticated', 'c@cb.local', '', now(), now());

insert into user_profiles (id, display_name) values
  ('00000000-0000-0000-0000-0000cb000001', 'Ada'),
  ('00000000-0000-0000-0000-0000cb000002', 'Bo'),
  ('00000000-0000-0000-0000-0000cb000003', 'Cy')
on conflict (id) do nothing;

insert into clubs (id, owner_id, name, slug, is_public) values
  ('cccccccc-cccc-cccc-cccc-cccccb000001', '00000000-0000-0000-0000-0000cb000001', 'Red', 'red-cb', true),
  ('cccccccc-cccc-cccc-cccc-cccccb000002', '00000000-0000-0000-0000-0000cb000002', 'Blue', 'blue-cb', true);

-- Distance challenge, fixed window so we can place runs in/out of it.
insert into challenges (id, creator_id, title, metric, scope, goal_value, starts_at, ends_at, is_public) values
  ('eeeeeeee-eeee-eeee-eeee-eeeecb000001', '00000000-0000-0000-0000-0000cb000001',
   'CB Distance', 'distance', 'individual', 100000,
   '2026-06-01 00:00:00+00', '2026-06-30 00:00:00+00', true);

-- Team challenge: Ada+Cy on Red, Bo on Blue.
insert into challenges (id, creator_id, title, metric, scope, starts_at, ends_at, is_public) values
  ('eeeeeeee-eeee-eeee-eeee-eeeecb000002', '00000000-0000-0000-0000-0000cb000001',
   'CB Team', 'distance', 'club_vs_club',
   '2026-06-01 00:00:00+00', '2026-06-30 00:00:00+00', true);

insert into challenge_participants (challenge_id, user_id) values
  ('eeeeeeee-eeee-eeee-eeee-eeeecb000001', '00000000-0000-0000-0000-0000cb000001'),
  ('eeeeeeee-eeee-eeee-eeee-eeeecb000001', '00000000-0000-0000-0000-0000cb000002');

insert into challenge_participants (challenge_id, user_id, team_club_id) values
  ('eeeeeeee-eeee-eeee-eeee-eeeecb000002', '00000000-0000-0000-0000-0000cb000001', 'cccccccc-cccc-cccc-cccc-cccccb000001'),
  ('eeeeeeee-eeee-eeee-eeee-eeeecb000002', '00000000-0000-0000-0000-0000cb000002', 'cccccccc-cccc-cccc-cccc-cccccb000002'),
  ('eeeeeeee-eeee-eeee-eeee-eeeecb000002', '00000000-0000-0000-0000-0000cb000003', 'cccccccc-cccc-cccc-cccc-cccccb000001');

-- June runs. Ada: 30k in-window. Bo: 50k in-window + a 99k OUT-of-window run
-- that must NOT count. Cy: 20k in-window (walk, to test the activity filter).
-- The streak runs live in JULY so they don't pollute the June distance board.
-- activity_type is a real column (defaults 'run'); the metadata key is separate.
-- Cy's run sets the COLUMN to 'walk' so the run-only filter excludes it.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, activity_type, metadata) values
  ('11111111-1111-1111-1111-1111cb000001', '00000000-0000-0000-0000-0000cb000001', '2026-06-05 08:00:00+00', 30000, 9000, 'app', true, 'run', '{"activity_type":"run"}'),
  ('11111111-1111-1111-1111-1111cb000002', '00000000-0000-0000-0000-0000cb000002', '2026-06-10 08:00:00+00', 50000, 15000, 'app', true, 'run', '{"activity_type":"run"}'),
  ('11111111-1111-1111-1111-1111cb000003', '00000000-0000-0000-0000-0000cb000002', '2026-05-20 08:00:00+00', 99000, 30000, 'app', true, 'run', '{"activity_type":"run"}'),
  ('11111111-1111-1111-1111-1111cb000004', '00000000-0000-0000-0000-0000cb000003', '2026-06-12 08:00:00+00', 20000, 6000, 'app', true, 'walk', '{"activity_type":"walk"}'),
  ('11111111-1111-1111-1111-1111cb000005', '00000000-0000-0000-0000-0000cb000001', '2026-07-05 19:00:00+00', 5000, 1500, 'app', true, 'run', '{"activity_type":"run"}'),
  ('11111111-1111-1111-1111-1111cb000006', '00000000-0000-0000-0000-0000cb000001', '2026-07-06 08:00:00+00', 5000, 1500, 'app', true, 'run', '{"activity_type":"run"}');

-- Extra challenges for the per-metric assertions (all seeded as table owner
-- before the RLS role switch).
insert into challenges (id, creator_id, title, metric, scope, activity_type, starts_at, ends_at, is_public) values
  ('eeeeeeee-eeee-eeee-eeee-eeeecb000003', '00000000-0000-0000-0000-0000cb000001',
   'CB Runs Only', 'distance', 'individual', 'run',
   '2026-06-01 00:00:00+00', '2026-06-30 00:00:00+00', true);
insert into challenges (id, creator_id, title, metric, scope, starts_at, ends_at, is_public) values
  ('eeeeeeee-eeee-eeee-eeee-eeeecb000004', '00000000-0000-0000-0000-0000cb000001',
   'CB Count', 'activity_count', 'individual',
   '2026-06-01 00:00:00+00', '2026-06-30 00:00:00+00', true),
  ('eeeeeeee-eeee-eeee-eeee-eeeecb000005', '00000000-0000-0000-0000-0000cb000001',
   'CB Days', 'streak_days', 'individual',
   '2026-07-01 00:00:00+00', '2026-07-31 00:00:00+00', true);
insert into challenge_participants (challenge_id, user_id) values
  ('eeeeeeee-eeee-eeee-eeee-eeeecb000003', '00000000-0000-0000-0000-0000cb000003'),
  ('eeeeeeee-eeee-eeee-eeee-eeeecb000004', '00000000-0000-0000-0000-0000cb000002'),
  ('eeeeeeee-eeee-eeee-eeee-eeeecb000005', '00000000-0000-0000-0000-0000cb000001');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000cb000001"}';

-- ── Individual board ──
-- Bo (50k) ranks above Ada (30k); Bo's out-of-window 99k does not count.
select results_eq(
  $$ select user_id, value::int, rank::int
     from challenge_leaderboard('eeeeeeee-eeee-eeee-eeee-eeeecb000001', false)
     order by rank, user_id $$,
  $$ values
       ('00000000-0000-0000-0000-0000cb000002'::uuid, 50000, 1),
       ('00000000-0000-0000-0000-0000cb000001'::uuid, 30000, 2) $$,
  'individual board: in-window sums, Bo>Ada, out-of-window excluded');

select is(
  (select display_name from challenge_leaderboard('eeeeeeee-eeee-eeee-eeee-eeeecb000001', false)
   where user_id = '00000000-0000-0000-0000-0000cb000001'),
  'Ada', 'leaderboard joins display_name');

-- ── activity_type filter — run-only challenge excludes Cy's walk ──
select is(
  (select value::int from challenge_leaderboard('eeeeeeee-eeee-eeee-eeee-eeeecb000003', false)
   where user_id = '00000000-0000-0000-0000-0000cb000003'),
  0, 'activity_type=run filter excludes a walk (value 0)');

-- ── activity_count metric ──
select is(
  (select value::int from challenge_leaderboard('eeeeeeee-eeee-eeee-eeee-eeeecb000004', false)
   where user_id = '00000000-0000-0000-0000-0000cb000002'),
  1, 'activity_count counts only the one in-window run');

-- ── streak_days metric — Jul 5 + Jul 6 = 2 distinct active days ──
select is(
  (select value::int from challenge_leaderboard('eeeeeeee-eeee-eeee-eeee-eeeecb000005', false)
   where user_id = '00000000-0000-0000-0000-0000cb000001'),
  2, 'streak_days counts distinct active days (Jul 5 + Jul 6 = 2)');

-- ── club_vs_club team grouping ──
-- Red = Ada(30k) + Cy(20k walk, but team challenge has no activity_type so it
-- counts) = 50k; Blue = Bo(50k) = 50k. Tie → rank 1 for both.
select results_eq(
  $$ select team_club_id, value::int, rank::int
     from challenge_leaderboard('eeeeeeee-eeee-eeee-eeee-eeeecb000002', true)
     order by team_club_id $$,
  $$ values
       ('cccccccc-cccc-cccc-cccc-cccccb000001'::uuid, 50000, 1),
       ('cccccccc-cccc-cccc-cccc-cccccb000002'::uuid, 50000, 1) $$,
  'club_vs_club: Red pools Ada+Cy=50k, Blue=Bo 50k, tie ranks both #1');

select is(
  (select count(*)::int from challenge_leaderboard('eeeeeeee-eeee-eeee-eeee-eeeecb000002', true)),
  2, 'team board returns one row per team, not per participant');

select * from finish();

rollback;
