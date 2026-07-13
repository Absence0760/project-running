-- Challenge goals exclude DNF runs (migration 20270407_001; bughunt-backend.md
-- finding #5). A DNF effort is not a completed activity, so it must not bank
-- progress toward a challenge goal or its leaderboard value — matching the
-- personal-records refresher (20261207_001) and achievements awarder
-- (20270208_001), which both filter `is_dnf = false`. Proves the DNF is
-- excluded from the distance aggregate + activity_count and cannot push a
-- runner over a goal.

begin;

select plan(4);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000cdf00001', 'authenticated', 'authenticated', 'a@cdf.local', '', now(), now());

insert into user_profiles (id, display_name) values
  ('00000000-0000-0000-0000-0000cdf00001', 'Ada') on conflict (id) do nothing;

-- Distance goal 100k, fixed window so runs land in/out deterministically.
insert into challenges (id, creator_id, title, metric, scope, goal_value, starts_at, ends_at, is_public) values
  ('eeeeeeee-eeee-eeee-eeee-eeeecdf00001', '00000000-0000-0000-0000-0000cdf00001',
   'CDF Distance', 'distance', 'individual', 100000,
   '2026-06-01 00:00:00+00', '2026-06-30 00:00:00+00', true);

-- Activity-count challenge over the same window.
insert into challenges (id, creator_id, title, metric, scope, starts_at, ends_at, is_public) values
  ('eeeeeeee-eeee-eeee-eeee-eeeecdf00002', '00000000-0000-0000-0000-0000cdf00001',
   'CDF Count', 'activity_count', 'individual',
   '2026-06-01 00:00:00+00', '2026-06-30 00:00:00+00', true);

insert into challenge_participants (challenge_id, user_id) values
  ('eeeeeeee-eeee-eeee-eeee-eeeecdf00001', '00000000-0000-0000-0000-0000cdf00001'),
  ('eeeeeeee-eeee-eeee-eeee-eeeecdf00002', '00000000-0000-0000-0000-0000cdf00001');

-- One completed 60k run (counts) + one DNF 60k run (must NOT count). If the DNF
-- counted, the distance board would read 120k and cross the 100k goal.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, is_dnf, metadata) values
  ('11111111-1111-1111-1111-1111cdf00001', '00000000-0000-0000-0000-0000cdf00001', '2026-06-05 08:00:00+00', 60000, 18000, 'app', true, false, '{"activity_type":"run"}'),
  ('11111111-1111-1111-1111-1111cdf00002', '00000000-0000-0000-0000-0000cdf00001', '2026-06-15 08:00:00+00', 60000, 18000, 'app', true, true,  '{"activity_type":"run"}');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000cdf00001"}';

-- ── leaderboard: DNF distance excluded (60k, not 120k) ──
select is(
  (select value::int from challenge_leaderboard('eeeeeeee-eeee-eeee-eeee-eeeecdf00001', false)
   where user_id = '00000000-0000-0000-0000-0000cdf00001'),
  60000, 'leaderboard sums only the completed run; the DNF 60k is excluded');

-- ── activity_count: DNF excluded from the count (1, not 2) ──
select is(
  (select value::int from challenge_leaderboard('eeeeeeee-eeee-eeee-eeee-eeeecdf00002', false)
   where user_id = '00000000-0000-0000-0000-0000cdf00001'),
  1, 'activity_count counts only the completed run, not the DNF');

-- ── completion: the DNF cannot push the runner over the 100k goal ──
select recompute_challenge_completion('eeeeeeee-eeee-eeee-eeee-eeeecdf00001', '00000000-0000-0000-0000-0000cdf00001');
select is(
  (select count(*)::int from challenge_badges where challenge_id = 'eeeeeeee-eeee-eeee-eeee-eeeecdf00001'),
  0, 'no badge: 60k completed < 100k goal, the DNF 60k does not count');
select is(
  (select completed_at from challenge_participants
   where challenge_id = 'eeeeeeee-eeee-eeee-eeee-eeeecdf00001'
     and user_id = '00000000-0000-0000-0000-0000cdf00001'),
  null, 'completed_at stays null: the DNF did not complete the goal');

select * from finish();

rollback;
