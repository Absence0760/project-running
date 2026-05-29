-- Pins migration 20261103_001 -- consent-gated coach run visibility (persona #47).
--
-- An active coach can read their athlete's runs (public AND private) and the
-- social rows hanging off them; a pending invite grants nothing; a stranger
-- and anon see nothing; the coach has no write path into the runs; the link
-- is athlete-scoped (no cross-athlete leak); ending the link revokes access.
begin;
select plan(25);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('cccccccc-0000-0000-0000-0000000000c1', 'authenticated', 'authenticated', 'coach@crv.local', '', now(), now()),
  ('cccccccc-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'athlete@crv.local', '', now(), now()),
  ('cccccccc-0000-0000-0000-0000000000b1', 'authenticated', 'authenticated', 'athlete2@crv.local', '', now(), now()),
  ('cccccccc-0000-0000-0000-0000000000e1', 'authenticated', 'authenticated', 'stranger@crv.local', '', now(), now());

-- Seed (as superuser, bypassing RLS): a PRIVATE and a PUBLIC run for the
-- athlete, plus a private run for a SECOND athlete the coach is not linked to.
-- is_public defaults false.
insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_public, metadata)
values
  ('cccccccc-0000-0000-0000-0000000000f1', 'cccccccc-0000-0000-0000-0000000000a1', now(), 1800, 5000, 'app', false, '{"activity_type":"run"}'),
  ('cccccccc-0000-0000-0000-0000000000f2', 'cccccccc-0000-0000-0000-0000000000a1', now(), 2400, 8000, 'app', true,  '{"activity_type":"run"}'),
  ('cccccccc-0000-0000-0000-0000000000d1', 'cccccccc-0000-0000-0000-0000000000b1', now(), 1200, 3000, 'app', false, '{"activity_type":"run"}');

-- A comment + a photo on the athlete's PRIVATE run, so we can prove the coach
-- inherits visibility of the is_run_visible_to-gated social tables.
insert into run_comments (run_id, author_id, body)
  values ('cccccccc-0000-0000-0000-0000000000f1', 'cccccccc-0000-0000-0000-0000000000a1', 'easy effort today');
insert into run_photos (run_id, owner_id, storage_path)
  values ('cccccccc-0000-0000-0000-0000000000f1', 'cccccccc-0000-0000-0000-0000000000a1',
          'cccccccc-0000-0000-0000-0000000000a1/photo1.jpg');

set local role authenticated;

-- ============================================================
-- Before any link: the coach is just a stranger
-- ============================================================
set local "request.jwt.claims" = '{"sub":"cccccccc-0000-0000-0000-0000000000c1","role":"authenticated"}';

select is(
  (select count(*)::int from runs where id = 'cccccccc-0000-0000-0000-0000000000f1'),
  0, 'an unlinked coach cannot read the athlete''s private run');

select ok(
  not private.is_run_visible_to('cccccccc-0000-0000-0000-0000000000f1', 'cccccccc-0000-0000-0000-0000000000c1'),
  'is_run_visible_to is false for an unlinked coach');

select ok(
  not private.is_active_coach_of('cccccccc-0000-0000-0000-0000000000c1', 'cccccccc-0000-0000-0000-0000000000a1'),
  'is_active_coach_of is false with no link');

-- ============================================================
-- A PENDING invite (minted, not redeemed) grants nothing
-- ============================================================
insert into coach_athletes (coach_id, status, invite_token)
  values ('cccccccc-0000-0000-0000-0000000000c1', 'pending', 'tok-crv-1');

select ok(
  not private.is_active_coach_of('cccccccc-0000-0000-0000-0000000000c1', 'cccccccc-0000-0000-0000-0000000000a1'),
  'a pending invite is not an active coaching link');

select is(
  (select count(*)::int from runs where id = 'cccccccc-0000-0000-0000-0000000000f1'),
  0, 'a coach with only a pending invite cannot read the athlete''s run');

-- ============================================================
-- Athlete redeems -> the link is active
-- ============================================================
set local "request.jwt.claims" = '{"sub":"cccccccc-0000-0000-0000-0000000000a1","role":"authenticated"}';
select redeem_coach_invite('tok-crv-1');

set local "request.jwt.claims" = '{"sub":"cccccccc-0000-0000-0000-0000000000c1","role":"authenticated"}';

select is(
  (select count(*)::int from runs where id = 'cccccccc-0000-0000-0000-0000000000f1'),
  1, 'an active coach can read the athlete''s private run');

select is(
  (select count(*)::int from runs where user_id = 'cccccccc-0000-0000-0000-0000000000a1'),
  2, 'an active coach reads ALL the athlete''s runs -- public and private alike');

select ok(
  private.is_run_visible_to('cccccccc-0000-0000-0000-0000000000f1', 'cccccccc-0000-0000-0000-0000000000c1'),
  'is_run_visible_to is true for an active coach on a private run');

select ok(
  private.is_run_visible_to('cccccccc-0000-0000-0000-0000000000f2', 'cccccccc-0000-0000-0000-0000000000c1'),
  'is_run_visible_to is true for an active coach on a public run');

select ok(
  private.is_active_coach_of('cccccccc-0000-0000-0000-0000000000c1', 'cccccccc-0000-0000-0000-0000000000a1'),
  'is_active_coach_of matches the live link');

select ok(
  not private.is_active_coach_of('cccccccc-0000-0000-0000-0000000000a1', 'cccccccc-0000-0000-0000-0000000000c1'),
  'is_active_coach_of is directional -- the athlete is not the coach''s coach');

-- The coach inherits visibility of the social tables gated by is_run_visible_to.
select is(
  (select count(*)::int from run_comments where run_id = 'cccccccc-0000-0000-0000-0000000000f1'),
  1, 'an active coach sees comments on the athlete''s private run');

select is(
  (select count(*)::int from run_photos where run_id = 'cccccccc-0000-0000-0000-0000000000f1'),
  1, 'an active coach sees photos on the athlete''s private run');

-- A coach can give feedback on the athlete's private run -- the INSERT
-- policies gate on the same is_run_visible_to, so the coach branch enables it.
-- (run_kudos blocks self-kudos by trigger, but the coach isn't the run owner.)
select lives_ok(
  $$insert into run_kudos (run_id, user_id)
    values ('cccccccc-0000-0000-0000-0000000000f1', 'cccccccc-0000-0000-0000-0000000000c1')$$,
  'an active coach can kudos the athlete''s private run');

select lives_ok(
  $$insert into run_comments (run_id, author_id, body)
    values ('cccccccc-0000-0000-0000-0000000000f1', 'cccccccc-0000-0000-0000-0000000000c1', 'great negative split')$$,
  'an active coach can comment on the athlete''s private run');

-- ============================================================
-- The link is athlete-scoped: no leak to other athletes' runs
-- ============================================================
select is(
  (select count(*)::int from runs where id = 'cccccccc-0000-0000-0000-0000000000d1'),
  0, 'a coach cannot read the run of an athlete they are NOT linked to');

select ok(
  not private.is_run_visible_to('cccccccc-0000-0000-0000-0000000000d1', 'cccccccc-0000-0000-0000-0000000000c1'),
  'is_run_visible_to is false for a run owned by an unlinked athlete');

-- ============================================================
-- The coach has no write path into the athlete's runs (SELECT-only tier).
-- "users own their runs" (FOR ALL) is the only write path and the coach
-- isn't the owner, so UPDATE/DELETE match no rows under RLS -- a silent
-- no-op, not a 42501. Assert the row is untouched.
-- ============================================================
update runs set distance_m = 1 where id = 'cccccccc-0000-0000-0000-0000000000f1';
select is(
  (select distance_m::int from runs where id = 'cccccccc-0000-0000-0000-0000000000f1'),
  5000, 'an active coach cannot modify the athlete''s run');

delete from runs where id = 'cccccccc-0000-0000-0000-0000000000f1';
select is(
  (select count(*)::int from runs where id = 'cccccccc-0000-0000-0000-0000000000f1'),
  1, 'an active coach cannot delete the athlete''s run');

-- ============================================================
-- A stranger still sees nothing
-- ============================================================
set local "request.jwt.claims" = '{"sub":"cccccccc-0000-0000-0000-0000000000e1","role":"authenticated"}';
select is(
  (select count(*)::int from runs where id = 'cccccccc-0000-0000-0000-0000000000f1'),
  0, 'a stranger cannot read the athlete''s private run');

select is(
  (select count(*)::int from run_comments where run_id = 'cccccccc-0000-0000-0000-0000000000f1'),
  0, 'a stranger cannot see comments on the athlete''s private run');

-- ============================================================
-- Anon: the coach policy must not accidentally grant unauthenticated reads
-- (auth.uid() is null -> is_active_coach_of(null, ...) is false).
-- ============================================================
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
select is(
  (select count(*)::int from runs where id = 'cccccccc-0000-0000-0000-0000000000f1'),
  0, 'anon cannot read the athlete''s private run through the coach policy');

-- ============================================================
-- Ending the link revokes everything immediately.
-- We flip the status as superuser (reset role) on purpose: HOW a link is
-- ended is #46's contract (currently the end_coach_link RPC, with no direct
-- UPDATE policy); this test owns only the #47 contract that an 'ended' link
-- yields no visibility, so it stays decoupled from the ending mechanism.
-- ============================================================
reset role;
update coach_athletes set status = 'ended', ended_at = now()
  where coach_id = 'cccccccc-0000-0000-0000-0000000000c1'
    and athlete_id = 'cccccccc-0000-0000-0000-0000000000a1';

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"cccccccc-0000-0000-0000-0000000000c1","role":"authenticated"}';

select is(
  (select count(*)::int from runs where id = 'cccccccc-0000-0000-0000-0000000000f1'),
  0, 'ending the link revokes the coach''s read access to the run');

select ok(
  not private.is_run_visible_to('cccccccc-0000-0000-0000-0000000000f1', 'cccccccc-0000-0000-0000-0000000000c1'),
  'is_run_visible_to is false again after the link ends');

select ok(
  not private.is_active_coach_of('cccccccc-0000-0000-0000-0000000000c1', 'cccccccc-0000-0000-0000-0000000000a1'),
  'is_active_coach_of is false once the link is ended');

select * from finish();
rollback;
