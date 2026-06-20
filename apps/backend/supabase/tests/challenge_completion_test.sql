-- recompute_challenge_completion (challenges.md; migration 20270210_001):
-- awards exactly one badge when the goal is met, is idempotent, respects
-- goal_value, stamps completed_at, and fires a 'challenge_complete'
-- notification. SECURITY DEFINER, so it counts the user's own runs regardless
-- of their is_public flag (a private run still progresses the owner's goal).

begin;

select plan(7);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000cc000001', 'authenticated', 'authenticated', 'a@cc.local', '', now(), now());

insert into user_profiles (id, display_name) values
  ('00000000-0000-0000-0000-0000cc000001', 'Ada') on conflict (id) do nothing;

-- 100k distance goal, currently-live window.
insert into challenges (id, creator_id, title, metric, scope, goal_value, starts_at, ends_at, is_public) values
  ('eeeeeeee-eeee-eeee-eeee-eeeecc000001', '00000000-0000-0000-0000-0000cc000001',
   'CC Goal', 'distance', 'individual', 100000,
   now() - interval '1 day', now() + interval '30 days', true);

insert into challenge_participants (challenge_id, user_id) values
  ('eeeeeeee-eeee-eeee-eeee-eeeecc000001', '00000000-0000-0000-0000-0000cc000001');

-- 60k of (private) running so far — below the 100k goal.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, metadata) values
  ('11111111-1111-1111-1111-1111cc000001', '00000000-0000-0000-0000-0000cc000001', now(), 60000, 18000, 'app', false, '{"activity_type":"run"}');

-- Below goal: no badge, no completion.
select recompute_challenge_completion('eeeeeeee-eeee-eeee-eeee-eeeecc000001', '00000000-0000-0000-0000-0000cc000001');
select is(
  (select count(*)::int from challenge_badges where challenge_id = 'eeeeeeee-eeee-eeee-eeee-eeeecc000001'),
  0, 'no badge while below goal');
select is(
  (select completed_at from challenge_participants
   where challenge_id = 'eeeeeeee-eeee-eeee-eeee-eeeecc000001'
     and user_id = '00000000-0000-0000-0000-0000cc000001'),
  null, 'completed_at stays null below goal');

-- Cross the line: another 50k → 110k total.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, metadata) values
  ('11111111-1111-1111-1111-1111cc000002', '00000000-0000-0000-0000-0000cc000001', now(), 50000, 15000, 'app', false, '{"activity_type":"run"}');

select recompute_challenge_completion('eeeeeeee-eeee-eeee-eeee-eeeecc000001', '00000000-0000-0000-0000-0000cc000001');
select is(
  (select count(*)::int from challenge_badges where challenge_id = 'eeeeeeee-eeee-eeee-eeee-eeeecc000001'),
  1, 'one badge awarded after crossing the goal');
select is(
  (select final_value::int from challenge_badges where challenge_id = 'eeeeeeee-eeee-eeee-eeee-eeeecc000001'),
  110000, 'badge records the final value (110k, including the private run)');
select isnt(
  (select completed_at from challenge_participants
   where challenge_id = 'eeeeeeee-eeee-eeee-eeee-eeeecc000001'
     and user_id = '00000000-0000-0000-0000-0000cc000001'),
  null, 'completed_at stamped on completion');
select is(
  (select count(*)::int from notifications
   where challenge_id = 'eeeeeeee-eeee-eeee-eeee-eeeecc000001'
     and kind = 'challenge_complete'),
  1, 'a challenge_complete notification was inserted');

-- Idempotent: a second recompute does not award a duplicate badge or notify again.
select recompute_challenge_completion('eeeeeeee-eeee-eeee-eeee-eeeecc000001', '00000000-0000-0000-0000-0000cc000001');
select is(
  (select count(*)::int from challenge_badges where challenge_id = 'eeeeeeee-eeee-eeee-eeee-eeeecc000001'),
  1, 'recompute is idempotent: still exactly one badge');

select * from finish();

rollback;
