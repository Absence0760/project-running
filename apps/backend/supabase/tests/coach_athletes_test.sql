-- Pins migration 20261102_001 — coach-athlete invite/accept model (persona #46).
-- Covers RLS insert/select/delete scoping, the redeem_coach_invite and
-- end_coach_link RPC guards, the no-direct-UPDATE consent invariant, live-pair
-- uniqueness, re-link after end, and FK cascade on account deletion.
begin;
select plan(24);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-0000-0000-0000-0000000000c1', 'authenticated', 'authenticated', 'coach@ca.local', '', now(), now()),
  ('aaaaaaaa-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'athlete-a@ca.local', '', now(), now()),
  ('aaaaaaaa-0000-0000-0000-0000000000b1', 'authenticated', 'authenticated', 'athlete-b@ca.local', '', now(), now()),
  ('aaaaaaaa-0000-0000-0000-0000000000e1', 'authenticated', 'authenticated', 'stranger@ca.local', '', now(), now());

set local role authenticated;

-- ===== coach mints invites =====
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c1","role":"authenticated"}';

select lives_ok(
  $$insert into coach_athletes (coach_id, status, invite_token)
    values ('aaaaaaaa-0000-0000-0000-0000000000c1', 'pending', 'tok-1')$$,
  'coach mints a pending invite for themselves');

select throws_ok(
  $$insert into coach_athletes (coach_id, status, invite_token)
    values ('aaaaaaaa-0000-0000-0000-0000000000a1', 'pending', 'tok-evil')$$,
  '42501', null, 'coach cannot mint an invite owned by someone else');

select throws_ok(
  $$insert into coach_athletes (coach_id, status, invite_token)
    values ('aaaaaaaa-0000-0000-0000-0000000000c1', 'active', 'tok-active')$$,
  '42501', null, 'coach cannot directly mint an active link (insert must be pending)');

select throws_ok(
  $$insert into coach_athletes (coach_id, athlete_id, status, invite_token)
    values ('aaaaaaaa-0000-0000-0000-0000000000c1', 'aaaaaaaa-0000-0000-0000-0000000000a1', 'pending', 'tok-preset')$$,
  '42501', null, 'coach cannot preset athlete_id on an invite (must be redeemed)');

select throws_ok(
  $$insert into coach_athletes (coach_id, status, invite_token)
    values ('aaaaaaaa-0000-0000-0000-0000000000c1', 'pending', 'tok-1')$$,
  '23505', null, 'invite_token is unique');

-- ===== a stranger cannot see the pending invite =====
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000e1","role":"authenticated"}';
select is(
  (select count(*)::int from coach_athletes where invite_token = 'tok-1'),
  0, 'a non-party cannot read the coach''s pending invite');

-- ===== athlete redeems =====
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000a1","role":"authenticated"}';
select is(redeem_coach_invite('tok-1'), 'aaaaaaaa-0000-0000-0000-0000000000c1'::uuid,
  'redeem_coach_invite returns the coach id');
select is((select status from coach_athletes where invite_token = 'tok-1'), 'active',
  'the link flips to active after redemption');
select is((select athlete_id from coach_athletes where invite_token = 'tok-1'),
  'aaaaaaaa-0000-0000-0000-0000000000a1'::uuid, 'the redeeming athlete is recorded');
select throws_ok($$select redeem_coach_invite('tok-1')$$,
  'invite not found or already redeemed', 'an already-redeemed token cannot be redeemed again');

-- ===== redeem requires an authenticated uid =====
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c1","role":"authenticated"}';
insert into coach_athletes (coach_id, status, invite_token)
  values ('aaaaaaaa-0000-0000-0000-0000000000c1', 'pending', 'tok-noauth');
set local "request.jwt.claims" = '{"role":"authenticated"}';
select throws_ok($$select redeem_coach_invite('tok-noauth')$$,
  'not authenticated', 'redeem requires an authenticated caller');

-- ===== self-coaching rejected =====
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c1","role":"authenticated"}';
insert into coach_athletes (coach_id, status, invite_token)
  values ('aaaaaaaa-0000-0000-0000-0000000000c1', 'pending', 'tok-self');
select throws_ok($$select redeem_coach_invite('tok-self')$$,
  'cannot coach yourself', 'a coach cannot redeem their own invite');

-- ===== double-link rejected =====
insert into coach_athletes (coach_id, status, invite_token)
  values ('aaaaaaaa-0000-0000-0000-0000000000c1', 'pending', 'tok-2');
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000a1","role":"authenticated"}';
select throws_ok($$select redeem_coach_invite('tok-2')$$,
  'already linked to this coach', 'an athlete already linked to a coach cannot redeem a second invite');

-- ===== consent invariant: no client UPDATE path =====
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c1","role":"authenticated"}';
update coach_athletes set athlete_id = 'aaaaaaaa-0000-0000-0000-0000000000b1' where invite_token = 'tok-1';
select is((select athlete_id from coach_athletes where invite_token = 'tok-1'),
  'aaaaaaaa-0000-0000-0000-0000000000a1'::uuid,
  'coach cannot reassign athlete_id via direct UPDATE (no UPDATE policy)');

update coach_athletes set athlete_id = 'aaaaaaaa-0000-0000-0000-0000000000b1', status = 'active' where invite_token = 'tok-self';
select is((select status from coach_athletes where invite_token = 'tok-self'), 'pending',
  'coach cannot forge an active link from a pending invite via direct UPDATE');

-- ===== end_coach_link =====
-- a non-party cannot end a link they can't see
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000e1","role":"authenticated"}';
select is(end_coach_link((select id from coach_athletes where invite_token = 'tok-1')), false,
  'a non-party cannot end a link');

-- a party (coach) ends the active link
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c1","role":"authenticated"}';
select is(end_coach_link((select id from coach_athletes where invite_token = 'tok-1')), true,
  'a party can end an active link');
select is((select status from coach_athletes where invite_token = 'tok-1'), 'ended',
  'status is ended after end_coach_link');

-- re-link works after a prior link ended (ended rows are excluded from the live unique index)
insert into coach_athletes (coach_id, status, invite_token)
  values ('aaaaaaaa-0000-0000-0000-0000000000c1', 'pending', 'tok-3');
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000a1","role":"authenticated"}';
select is(redeem_coach_invite('tok-3'), 'aaaaaaaa-0000-0000-0000-0000000000c1'::uuid,
  'an athlete can re-link to a coach after a prior link ended');
select is(end_coach_link((select id from coach_athletes where invite_token = 'tok-3')), true,
  'the athlete side can also end a link');

-- ===== delete (revoke) policy =====
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c1","role":"authenticated"}';
delete from coach_athletes where invite_token = 'tok-2';
select is((select count(*)::int from coach_athletes where invite_token = 'tok-2'), 0,
  'a coach can revoke (delete) a pending invite');

-- an active link cannot be deleted by either party (delete policy is pending-only)
insert into coach_athletes (coach_id, status, invite_token)
  values ('aaaaaaaa-0000-0000-0000-0000000000c1', 'pending', 'tok-b');
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000b1","role":"authenticated"}';
select redeem_coach_invite('tok-b');

set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c1","role":"authenticated"}';
delete from coach_athletes where invite_token = 'tok-b';
select is((select count(*)::int from coach_athletes where invite_token = 'tok-b'), 1,
  'a coach cannot DELETE an active link (only pending invites)');

set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000b1","role":"authenticated"}';
delete from coach_athletes where invite_token = 'tok-b';
select is((select count(*)::int from coach_athletes where invite_token = 'tok-b'), 1,
  'an athlete cannot DELETE a link');

-- ===== account deletion cascades =====
reset role;
reset "request.jwt.claims";
delete from auth.users where id = 'aaaaaaaa-0000-0000-0000-0000000000b1';
select is(
  (select count(*)::int from coach_athletes
     where coach_id = 'aaaaaaaa-0000-0000-0000-0000000000b1'
        or athlete_id = 'aaaaaaaa-0000-0000-0000-0000000000b1'),
  0, 'deleting a user cascades to their coach_athletes rows');

select * from finish();
rollback;
