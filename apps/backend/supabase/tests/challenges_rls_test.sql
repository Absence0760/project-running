-- Challenges RLS matrix (challenges.md; migration 20270206_001). Proves the
-- fail-closed visibility + write gates across creator / member / outsider /
-- anon, the join eligibility gate, and the completed_at column lockdown.

begin;

select plan(15);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000ca000001', 'authenticated', 'authenticated',
   'creator@ca.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000ca000002', 'authenticated', 'authenticated',
   'member@ca.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000ca000003', 'authenticated', 'authenticated',
   'outsider@ca.local', '', now(), now());

insert into user_profiles (id, display_name)
values
  ('00000000-0000-0000-0000-0000ca000001', 'Creator'),
  ('00000000-0000-0000-0000-0000ca000002', 'Member'),
  ('00000000-0000-0000-0000-0000ca000003', 'Outsider')
on conflict (id) do nothing;

-- A private club the creator owns (auto-enrolls them as owner); member joins it.
insert into clubs (id, owner_id, name, slug, is_public)
values
  ('cccccccc-cccc-cccc-cccc-ccccca000001',
   '00000000-0000-0000-0000-0000ca000001', 'CA Club', 'ca-club', false);

insert into club_members (club_id, user_id, role, status)
values
  ('cccccccc-cccc-cccc-cccc-ccccca000001', '00000000-0000-0000-0000-0000ca000002', 'member', 'active');

-- A public open challenge + a private club-anchored one.
insert into challenges (id, creator_id, club_id, title, metric, scope, goal_value, starts_at, ends_at, is_public)
values
  ('eeeeeeee-eeee-eeee-eeee-eeeeca000001',
   '00000000-0000-0000-0000-0000ca000001', null,
   'Open 100k', 'distance', 'individual', 100000,
   now() - interval '1 day', now() + interval '30 days', true),
  ('eeeeeeee-eeee-eeee-eeee-eeeeca000002',
   '00000000-0000-0000-0000-0000ca000001', 'cccccccc-cccc-cccc-cccc-ccccca000001',
   'Club Co-op', 'distance', 'group_goal', 500000,
   now() - interval '1 day', now() + interval '30 days', false);

-- ───────────────── SELECT visibility ─────────────────
set local role authenticated;

-- Outsider sees the public challenge but NOT the private club one.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000ca000003"}';
select is(
  (select count(*)::int from challenges where id = 'eeeeeeee-eeee-eeee-eeee-eeeeca000001'),
  1, 'outsider sees the public challenge');
select is(
  (select count(*)::int from challenges where id = 'eeeeeeee-eeee-eeee-eeee-eeeeca000002'),
  0, 'outsider CANNOT see the private club challenge (fail-closed)');

-- Club member sees the private club challenge.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000ca000002"}';
select is(
  (select count(*)::int from challenges where id = 'eeeeeeee-eeee-eeee-eeee-eeeeca000002'),
  1, 'club member sees the private club challenge');

-- Anon sees only the public challenge.
set local role anon;
select set_config('request.jwt.claims', null, true);
select is(
  (select count(*)::int from challenges where id = 'eeeeeeee-eeee-eeee-eeee-eeeeca000001'),
  1, 'anon sees the public challenge');
select is(
  (select count(*)::int from challenges where id = 'eeeeeeee-eeee-eeee-eeee-eeeeca000002'),
  0, 'anon CANNOT see the private club challenge');

-- ───────────────── INSERT gates ─────────────────
set local role authenticated;

-- Anyone authenticated can create an OPEN challenge.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000ca000003"}';
select lives_ok(
  $$ insert into challenges (creator_id, club_id, title, metric, scope, starts_at, ends_at)
     values ('00000000-0000-0000-0000-0000ca000003', null, 'Outsider Open', 'distance',
             'individual', now(), now() + interval '7 days') $$,
  'any authenticated user can create an open challenge');

-- A non-admin CANNOT create a club-anchored challenge.
select throws_ok(
  $$ insert into challenges (creator_id, club_id, title, metric, scope, starts_at, ends_at)
     values ('00000000-0000-0000-0000-0000ca000003',
             'cccccccc-cccc-cccc-cccc-ccccca000001', 'Sneaky Club', 'distance',
             'individual', now(), now() + interval '7 days') $$,
  '42501', null, 'non-admin cannot create a club-anchored challenge (RLS)');

-- Creator cannot forge creator_id as someone else.
select throws_ok(
  $$ insert into challenges (creator_id, club_id, title, metric, scope, starts_at, ends_at)
     values ('00000000-0000-0000-0000-0000ca000001', null, 'Forged', 'distance',
             'individual', now(), now() + interval '7 days') $$,
  '42501', null, 'cannot create a challenge with someone else''s creator_id');

-- ───────────────── UPDATE / DELETE gates ─────────────────
-- Outsider's UPDATE of the creator's open challenge affects 0 rows (RLS hides
-- the row from the UPDATE's USING clause).
update challenges set title = 'Hijacked' where id = 'eeeeeeee-eeee-eeee-eeee-eeeeca000001';
select is(
  (select title from challenges where id = 'eeeeeeee-eeee-eeee-eeee-eeeeca000001'),
  'Open 100k', 'outsider UPDATE of another user''s challenge changed nothing');

-- Creator can update their own.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000ca000001"}';
update challenges set title = 'Open 100k v2' where id = 'eeeeeeee-eeee-eeee-eeee-eeeeca000001';
select is(
  (select title from challenges where id = 'eeeeeeee-eeee-eeee-eeee-eeeeca000001'),
  'Open 100k v2', 'creator can update their own challenge');

-- ───────────────── JOIN eligibility ─────────────────
-- Outsider can join a visible (public) challenge.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000ca000003"}';
select lives_ok(
  $$ insert into challenge_participants (challenge_id, user_id)
     values ('eeeeeeee-eeee-eeee-eeee-eeeeca000001', '00000000-0000-0000-0000-0000ca000003') $$,
  'a user can join a visible public challenge');

-- Outsider cannot join the private club challenge (not visible).
select throws_ok(
  $$ insert into challenge_participants (challenge_id, user_id)
     values ('eeeeeeee-eeee-eeee-eeee-eeeeca000002', '00000000-0000-0000-0000-0000ca000003') $$,
  '42501', null, 'cannot join an invisible challenge');

-- Cannot join as another user.
select throws_ok(
  $$ insert into challenge_participants (challenge_id, user_id)
     values ('eeeeeeee-eeee-eeee-eeee-eeeeca000001', '00000000-0000-0000-0000-0000ca000001') $$,
  '42501', null, 'cannot join on behalf of another user');

-- ───────────────── completed_at column lockdown ─────────────────
-- The participant's own UPDATE touching completed_at is rejected (column grant
-- revoked); the SECURITY DEFINER RPC is the sole writer.
select throws_ok(
  $$ update challenge_participants set completed_at = now()
     where challenge_id = 'eeeeeeee-eeee-eeee-eeee-eeeeca000001'
       and user_id = '00000000-0000-0000-0000-0000ca000003' $$,
  '42501', null, 'a participant cannot write their own completed_at (column lockdown)');

-- They CAN change their own team_club_id (the one granted column).
select lives_ok(
  $$ update challenge_participants set team_club_id = null
     where challenge_id = 'eeeeeeee-eeee-eeee-eeee-eeeeca000001'
       and user_id = '00000000-0000-0000-0000-0000ca000003' $$,
  'a participant can update their own team_club_id (granted column)');

select * from finish();

rollback;
