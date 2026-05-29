-- Pins migration 20261102_001 — coach-athlete invite/accept model (persona #46).
-- Covers the RLS insert/select scoping and the redeem_coach_invite RPC's guards.
begin;
select plan(9);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-0000-0000-0000-0000000000c1', 'authenticated', 'authenticated', 'coach@ca.local', '', now(), now()),
  ('aaaaaaaa-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'athlete@ca.local', '', now(), now()),
  ('aaaaaaaa-0000-0000-0000-0000000000e1', 'authenticated', 'authenticated', 'stranger@ca.local', '', now(), now());

-- === coach mints an invite ===
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c1","role":"authenticated"}';

select lives_ok(
  $$insert into coach_athletes (coach_id, status, invite_token)
    values ('aaaaaaaa-0000-0000-0000-0000000000c1', 'pending', 'tok-athlete-1')$$,
  'coach can mint a pending invite for themselves');

select throws_ok(
  $$insert into coach_athletes (coach_id, status, invite_token)
    values ('aaaaaaaa-0000-0000-0000-0000000000a1', 'pending', 'tok-evil')$$,
  '42501', null,
  'coach cannot mint an invite owned by someone else (RLS)');

-- === a stranger cannot see the coach's pending invite ===
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000e1","role":"authenticated"}';
select is(
  (select count(*)::int from coach_athletes where invite_token = 'tok-athlete-1'),
  0,
  'a non-party cannot read the coach''s pending invite (RLS)');

-- === the athlete redeems the invite ===
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000a1","role":"authenticated"}';
select is(
  redeem_coach_invite('tok-athlete-1'),
  'aaaaaaaa-0000-0000-0000-0000000000c1'::uuid,
  'redeem_coach_invite returns the coach id');

select is(
  (select status from coach_athletes where invite_token = 'tok-athlete-1'),
  'active',
  'the link flips to active after redemption');

select is(
  (select athlete_id from coach_athletes where invite_token = 'tok-athlete-1'),
  'aaaaaaaa-0000-0000-0000-0000000000a1'::uuid,
  'the redeeming athlete is recorded on the link');

select throws_ok(
  $$select redeem_coach_invite('tok-athlete-1')$$,
  'invite not found or already redeemed',
  'an already-redeemed token cannot be redeemed again');

-- === self-coaching is rejected ===
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c1","role":"authenticated"}';
insert into coach_athletes (coach_id, status, invite_token)
  values ('aaaaaaaa-0000-0000-0000-0000000000c1', 'pending', 'tok-self');
select throws_ok(
  $$select redeem_coach_invite('tok-self')$$,
  'cannot coach yourself',
  'a coach cannot redeem their own invite');

-- === a second link to the same coach is rejected ===
insert into coach_athletes (coach_id, status, invite_token)
  values ('aaaaaaaa-0000-0000-0000-0000000000c1', 'pending', 'tok-athlete-2');
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000a1","role":"authenticated"}';
select throws_ok(
  $$select redeem_coach_invite('tok-athlete-2')$$,
  'already linked to this coach',
  'an athlete already linked to a coach cannot redeem a second invite from them');

select * from finish();
rollback;
