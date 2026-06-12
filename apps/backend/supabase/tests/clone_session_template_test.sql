-- Pins migration 20270104_001 (clone_session_template). session_planner.md P3.
--
-- Authorisation + copy contract (mirrors clone_plan_template):
--   1. A club member may clone a club-owned session template into a new
--      PERSONAL plan (author = caller, club_id = null, is_public = false).
--   2. The copy carries the head + blocks + items (per_side preserved); the
--      template is left untouched.
--   3. A non-member of the owning club is rejected (not authorised).
--   4. The template author may clone their own plan even with no club.

begin;
select plan(8);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('99999999-0000-0000-0000-0000000c5001', 'authenticated', 'authenticated', 'author@cst.local', '', now(), now()),
  ('99999999-0000-0000-0000-0000000c5002', 'authenticated', 'authenticated', 'member@cst.local', '', now(), now()),
  ('99999999-0000-0000-0000-0000000c5003', 'authenticated', 'authenticated', 'stranger@cst.local', '', now(), now());

-- Club owned by the author (enroll trigger makes them an owner-member); the
-- member joins it. The stranger never joins.
insert into clubs (id, owner_id, name, slug)
values ('cccccccc-0000-0000-0000-0000000c5001',
        '99999999-0000-0000-0000-0000000c5001', 'CST Club', 'cst-club');

insert into club_members (club_id, user_id, role, status)
values ('cccccccc-0000-0000-0000-0000000c5001',
        '99999999-0000-0000-0000-0000000c5002', 'member', 'active');

-- A club-owned session template: one block + a per-side hold + a blockless reps
-- item, so the copy exercises both the blocked and blockless item paths.
insert into session_plans (id, author_id, club_id, title, discipline, equipment, is_public)
values ('11111111-0000-0000-0000-0000000c5001',
        '99999999-0000-0000-0000-0000000c5001',
        'cccccccc-0000-0000-0000-0000000c5001',
        'CST Flow', 'Vinyasa', 'Mat', false);

insert into session_plan_blocks (id, plan_id, position, name)
values ('bbbbbbbb-0000-0000-0000-0000000c5001',
        '11111111-0000-0000-0000-0000000c5001', 0, 'Standing');

insert into session_plan_items (plan_id, block_id, position, movement_name, kind, duration_s, per_side)
values ('11111111-0000-0000-0000-0000000c5001',
        'bbbbbbbb-0000-0000-0000-0000000c5001', 0, 'Warrior II', 'hold', 45, true);
insert into session_plan_items (plan_id, block_id, position, movement_name, kind, reps, per_side)
values ('11111111-0000-0000-0000-0000000c5001', null, 1, 'The Hundred', 'reps', 100, false);

set local role authenticated;

-- ============================================================
-- 1. a club member clones the template into a personal plan
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-0000000c5002","role":"authenticated"}';
select lives_ok(
  $$select clone_session_template('11111111-0000-0000-0000-0000000c5001')$$,
  'a club member can clone a club session template'
);

-- The member now owns exactly one personal copy (club_id null, private).
select is(
  (select count(*)::int from session_plans
     where author_id = '99999999-0000-0000-0000-0000000c5002'
       and title = 'CST Flow' and club_id is null and is_public = false),
  1, 'clone is a personal, private, club-less copy owned by the caller');

-- The copy carries both items, with per_side preserved on the hold.
select is(
  (select count(*)::int from session_plan_items i
     join session_plans p on p.id = i.plan_id
     where p.author_id = '99999999-0000-0000-0000-0000000c5002' and p.title = 'CST Flow'),
  2, 'clone copies both items');
select is(
  (select i.per_side from session_plan_items i
     join session_plans p on p.id = i.plan_id
     where p.author_id = '99999999-0000-0000-0000-0000000c5002'
       and p.title = 'CST Flow' and i.movement_name = 'Warrior II'),
  true, 'per_side is preserved on the cloned hold');
select is(
  (select i.block_id is not null from session_plan_items i
     join session_plans p on p.id = i.plan_id
     where p.author_id = '99999999-0000-0000-0000-0000000c5002'
       and p.title = 'CST Flow' and i.movement_name = 'Warrior II'),
  true, 'a blocked item keeps a (new) block in the clone');

-- The template itself is untouched (still club-owned, still 2 items).
select is(
  (select club_id from session_plans where id = '11111111-0000-0000-0000-0000000c5001'),
  'cccccccc-0000-0000-0000-0000000c5001'::uuid,
  'the source template is left club-owned');

-- ============================================================
-- 2. a non-member is rejected
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-0000000c5003","role":"authenticated"}';
select throws_ok(
  $$select clone_session_template('11111111-0000-0000-0000-0000000c5001')$$,
  'P0001',
  'clone_session_template: not authorised to clone template 11111111-0000-0000-0000-0000000c5001',
  'a non-member of the owning club cannot clone the template'
);

-- ============================================================
-- 3. the author can clone their own plan
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-0000000c5001","role":"authenticated"}';
select lives_ok(
  $$select clone_session_template('11111111-0000-0000-0000-0000000c5001')$$,
  'the template author can clone their own plan'
);

select finish();
rollback;
