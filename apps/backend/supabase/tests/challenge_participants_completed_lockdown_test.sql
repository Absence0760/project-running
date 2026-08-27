-- completed_at column lockdown (challenges.md; migration 20270209_001):
-- a direct client UPDATE of challenge_participants.completed_at is rejected by
-- the column-grant revoke, while the SECURITY DEFINER completion RPC writes it
-- successfully. Mirrors the event_attendees attendance lockdown idiom.

begin;

select plan(5);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000cd000001', 'authenticated', 'authenticated', 'a@cd.local', '', now(), now());

insert into user_profiles (id, display_name) values
  ('00000000-0000-0000-0000-0000cd000001', 'Ada') on conflict (id) do nothing;

insert into challenges (id, creator_id, title, metric, scope, goal_value, starts_at, ends_at, is_public) values
  ('eeeeeeee-eeee-eeee-eeee-eeeecd000001', '00000000-0000-0000-0000-0000cd000001',
   'CD Goal', 'distance', 'individual', 1000,
   now() - interval '1 day', now() + interval '30 days', true);

insert into challenge_participants (challenge_id, user_id) values
  ('eeeeeeee-eeee-eeee-eeee-eeeecd000001', '00000000-0000-0000-0000-0000cd000001');

insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, metadata) values
  ('11111111-1111-1111-1111-1111cd000001', '00000000-0000-0000-0000-0000cd000001', now(), 5000, 1500, 'app', false, '{"activity_type":"run"}');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000cd000001"}';

-- Direct client write of completed_at is rejected (no column grant).
select throws_ok(
  $$ update challenge_participants set completed_at = now()
     where challenge_id = 'eeeeeeee-eeee-eeee-eeee-eeeecd000001'
       and user_id = '00000000-0000-0000-0000-0000cd000001' $$,
  '42501', null, 'direct client completed_at write rejected (column lockdown)');

-- The RPC (SECURITY DEFINER) writes it.
select lives_ok(
  $$ select recompute_challenge_completion(
       'eeeeeeee-eeee-eeee-eeee-eeeecd000001', '00000000-0000-0000-0000-0000cd000001') $$,
  'the completion RPC runs as the participant');
select isnt(
  (select completed_at from challenge_participants
   where challenge_id = 'eeeeeeee-eeee-eeee-eeee-eeeecd000001'
     and user_id = '00000000-0000-0000-0000-0000cd000001'),
  null, 'the RPC successfully wrote completed_at');

-- The UPDATE lockdown only locks anything while the same client cannot reach
-- the column through INSERT. Joining and leaving are both own-row verbs here,
-- so until 20270616_001 a participant could delete their own row and re-insert
-- it with completed_at already set — two statements, no RPC, the forged
-- completion then rendering as "completed" on their challenge list. That is
-- decisions.md 584's class, closed for event_attendees by 20270520_001 and
-- pinned schema-wide by column_grant_write_lockdown_registry_test.
--
-- The DELETE below is the exploit's first half and stays permitted (leaving a
-- challenge is a real affordance). It also makes the re-INSERT otherwise
-- VALID — same visible challenge, same auth.uid(), no primary-key collision —
-- so the only thing left that can refuse it is the absent column grant. An
-- assertion that pointed at a non-existent challenge would raise the same
-- 42501 from the WITH CHECK and pass before the fix as happily as after it.
delete from challenge_participants
 where challenge_id = 'eeeeeeee-eeee-eeee-eeee-eeeecd000001'
   and user_id = '00000000-0000-0000-0000-0000cd000001';

select throws_ok(
  $$ insert into challenge_participants (challenge_id, user_id, completed_at)
     values ('eeeeeeee-eeee-eeee-eeee-eeeecd000001',
             '00000000-0000-0000-0000-0000cd000001', now()) $$,
  '42501', null,
  'completed_at cannot be written at INSERT either — DELETE + re-INSERT was the way round the UPDATE lockdown');

-- And the honest rejoin, which is what the grant does allow, leaves the
-- completion unset: leaving and rejoining resets it rather than preserving it.
insert into challenge_participants (challenge_id, user_id)
values ('eeeeeeee-eeee-eeee-eeee-eeeecd000001',
        '00000000-0000-0000-0000-0000cd000001');
select is(
  (select completed_at from challenge_participants
   where challenge_id = 'eeeeeeee-eeee-eeee-eeee-eeeecd000001'
     and user_id = '00000000-0000-0000-0000-0000cd000001'),
  null, 'rejoining leaves completed_at unset — a client cannot carry it back in');

select * from finish();

rollback;
