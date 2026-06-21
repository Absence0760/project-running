-- recompute_challenge_completion(p_challenge_id, p_user_id) must not let an
-- authenticated caller drive another user's completion. The RPC is SECURITY
-- DEFINER and accepted any p_user_id, so an attacker could call it with a
-- victim's id and force a badge / completed_at stamp / 'challenge_complete'
-- notification onto the victim's account (and aggregate over the victim's
-- private runs) the moment the victim genuinely crossed the goal. The fix
-- mirrors job_scheduled_at_for_user (20260914_001): block when auth.uid() is
-- set and differs from p_user_id, while leaving the null-uid cron/service path
-- (sweep_challenge_completions) intact.

begin;

select plan(4);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000dd000001', 'authenticated', 'authenticated', 'victim@dd.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000dd000002', 'authenticated', 'authenticated', 'attacker@dd.local', '', now(), now());

insert into user_profiles (id, display_name) values
  ('00000000-0000-0000-0000-0000dd000001', 'Victim'),
  ('00000000-0000-0000-0000-0000dd000002', 'Attacker') on conflict (id) do nothing;

insert into challenges (id, creator_id, title, metric, scope, goal_value, starts_at, ends_at, is_public) values
  ('eeeeeeee-eeee-eeee-eeee-eeeedd000001', '00000000-0000-0000-0000-0000dd000001',
   'DD Goal', 'distance', 'individual', 100000,
   now() - interval '1 day', now() + interval '30 days', true);

-- The victim is a participant who has genuinely already crossed the 100k goal.
insert into challenge_participants (challenge_id, user_id) values
  ('eeeeeeee-eeee-eeee-eeee-eeeedd000001', '00000000-0000-0000-0000-0000dd000001');

insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, metadata) values
  ('11111111-1111-1111-1111-1111dd000001', '00000000-0000-0000-0000-0000dd000001', now(), 120000, 36000, 'app', false, '{"activity_type":"run"}');

-- The attacker is signed in. They try to drive the VICTIM's completion.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000dd000002","role":"authenticated"}';

select throws_ok(
  $$ select recompute_challenge_completion('eeeeeeee-eeee-eeee-eeee-eeeedd000001', '00000000-0000-0000-0000-0000dd000001') $$,
  '42501',
  null,
  'an authenticated caller cannot recompute another user''s completion');

reset role;
select set_config('request.jwt.claims', null, true);

-- The attacker's call must not have written anything to the victim's account.
select is(
  (select count(*)::int from challenge_badges where challenge_id = 'eeeeeeee-eeee-eeee-eeee-eeeedd000001'),
  0, 'no badge forged onto the victim by another caller');
select is(
  (select count(*)::int from notifications where challenge_id = 'eeeeeeee-eeee-eeee-eeee-eeeedd000001'),
  0, 'no notification forged onto the victim by another caller');

-- The cron/service path (auth.uid() is null) must still work: it awards the
-- victim their genuinely-earned badge.
select recompute_challenge_completion('eeeeeeee-eeee-eeee-eeee-eeeedd000001', '00000000-0000-0000-0000-0000dd000001');
select is(
  (select count(*)::int from challenge_badges where challenge_id = 'eeeeeeee-eeee-eeee-eeee-eeeedd000001'),
  1, 'the null-uid cron/sweep path still awards the earned badge');

select * from finish();

rollback;
