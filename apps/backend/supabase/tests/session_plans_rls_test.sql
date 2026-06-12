-- Pins migration 20270103_001 (session_plans / _blocks / _items + the
-- events.session_plan_id attach point). session_planner.md P1.
--
-- RLS contract (mirrors club-owned routes, 20260520_001):
--   1. author reads + writes their OWN plan; a stranger sees nothing of a
--      private plan.
--   2. is_public = true is world-readable.
--   3. a club-owned plan is readable by any club member and writable only by a
--      club admin (a plain member cannot write).
--   4. session_plan_items.kind is CHECK-constrained to hold|reps|flow.
--   5. events.session_plan_id may be set ONLY by an event organiser (the
--      enforce_event_session_plan_organiser trigger) — a plain member is
--      rejected 42501.

begin;
select plan(13);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('99999999-0000-0000-0000-00000000a001', 'authenticated', 'authenticated', 'author@sp.local', '', now(), now()),
  ('99999999-0000-0000-0000-00000000a002', 'authenticated', 'authenticated', 'stranger@sp.local', '', now(), now()),
  ('99999999-0000-0000-0000-00000000a003', 'authenticated', 'authenticated', 'admin@sp.local', '', now(), now()),
  ('99999999-0000-0000-0000-00000000a004', 'authenticated', 'authenticated', 'member@sp.local', '', now(), now());

-- Club owned by the admin (the enroll_club_owner trigger auto-adds the owner as
-- an active 'owner' member); the plain member joins it (superuser, RLS bypassed).
insert into clubs (id, owner_id, name, slug)
values ('cccccccc-0000-0000-0000-00000000c001',
        '99999999-0000-0000-0000-00000000a003', 'Session Club', 'session-club');

insert into club_members (club_id, user_id, role, status)
values
  ('cccccccc-0000-0000-0000-00000000c001', '99999999-0000-0000-0000-00000000a004', 'member', 'active');

-- A PRIVATE author-owned plan, a PUBLIC author-owned plan, and a CLUB-owned plan.
insert into session_plans (id, author_id, club_id, title, is_public)
values
  ('11111111-0000-0000-0000-00000000af01', '99999999-0000-0000-0000-00000000a001', null, 'Private Flow', false),
  ('11111111-0000-0000-0000-00000000af02', '99999999-0000-0000-0000-00000000a001', null, 'Public Flow', true),
  ('11111111-0000-0000-0000-00000000af03', '99999999-0000-0000-0000-00000000a003', 'cccccccc-0000-0000-0000-00000000c001', 'Club Flow', false);

insert into session_plan_items (plan_id, position, movement_name, kind, duration_s)
values ('11111111-0000-0000-0000-00000000af01', 0, 'Downward Dog', 'hold', 30);

-- A class event in the club, authored by the admin.
insert into events (id, club_id, author_id, title, category, starts_at)
values ('eeeeeeee-0000-0000-0000-00000000ee01',
        'cccccccc-0000-0000-0000-00000000c001',
        '99999999-0000-0000-0000-00000000a003',
        'Yoga class', 'class', now() + interval '7 days');

set local role authenticated;

-- ============================================================
-- 1. author reads + writes own; stranger sees nothing of a private plan
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000a001","role":"authenticated"}';
select is(
  (select count(*)::int from session_plans where id = '11111111-0000-0000-0000-00000000af01'),
  1, 'author reads their own private plan');
select lives_ok(
  $$ update session_plans set title = 'Private Flow v2' where id = '11111111-0000-0000-0000-00000000af01' $$,
  'author updates their own plan');

set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000a002","role":"authenticated"}';
select is(
  (select count(*)::int from session_plans where id = '11111111-0000-0000-0000-00000000af01'),
  0, 'a stranger cannot read another user''s private plan');

-- ============================================================
-- 2. is_public is world-readable
-- ============================================================
select is(
  (select count(*)::int from session_plans where id = '11111111-0000-0000-0000-00000000af02'),
  1, 'a stranger reads a public plan');
select is(
  (select count(*)::int from session_plans where id = '11111111-0000-0000-0000-00000000af03'),
  0, 'a stranger (non-member) cannot read a private club-owned plan');

-- ============================================================
-- 3. club-owned: member reads, admin writes, member cannot write
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000a004","role":"authenticated"}';
select is(
  (select count(*)::int from session_plans where id = '11111111-0000-0000-0000-00000000af03'),
  1, 'a club member reads the club-owned plan');
-- A member UPDATE is RLS-filtered (no admin write policy matches) → 0 rows.
select lives_ok(
  $$ update session_plans set title = 'hacked' where id = '11111111-0000-0000-0000-00000000af03' $$,
  'a club member''s update runs but is RLS-filtered');
select is(
  (select title from session_plans where id = '11111111-0000-0000-0000-00000000af03'),
  'Club Flow', 'the club plan title is unchanged by a plain member');

set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000a003","role":"authenticated"}';
select lives_ok(
  $$ update session_plans set title = 'Club Flow v2' where id = '11111111-0000-0000-0000-00000000af03' $$,
  'a club admin updates the club-owned plan');

-- ============================================================
-- 4. session_plan_items.kind CHECK (hold|reps|flow)
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000a001","role":"authenticated"}';
select throws_ok(
  $$ insert into session_plan_items (plan_id, position, movement_name, kind)
     values ('11111111-0000-0000-0000-00000000af01', 1, 'Bad', 'sprint') $$,
  '23514',
  null,
  'an invalid item kind is rejected by the CHECK');

-- ============================================================
-- 5. events.session_plan_id is organiser-write only
-- ============================================================
-- A plain member (a004) cannot attach the plan: the events UPDATE RLS policy
-- ("organisers can edit events") filters the row to zero, so the write is a
-- no-op (and the BEFORE trigger is a defence-in-depth second layer behind it).
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000a004","role":"authenticated"}';
select lives_ok(
  $$ update events set session_plan_id = '11111111-0000-0000-0000-00000000af02'
     where id = 'eeeeeeee-0000-0000-0000-00000000ee01' $$,
  'a plain member''s attach runs but is RLS-filtered to zero rows');
-- Read back as the organiser (who can SELECT the event) to confirm no change.
select is(
  (select session_plan_id from events where id = 'eeeeeeee-0000-0000-0000-00000000ee01'),
  null,
  'the event has no plan attached after the plain member''s write')
  from (select set_config('request.jwt.claims', '{"sub":"99999999-0000-0000-0000-00000000a003","role":"authenticated"}', true)) _;

-- The club owner (an organiser) can attach it.
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000a003","role":"authenticated"}';
select lives_ok(
  $$ update events set session_plan_id = '11111111-0000-0000-0000-00000000af02'
     where id = 'eeeeeeee-0000-0000-0000-00000000ee01' $$,
  'an event organiser attaches a session plan');

reset role;
select * from finish();
rollback;
