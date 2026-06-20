-- Pins migration 20270227_001 (gear_rotations — named multi-pair gear groups).
--
-- gear_rotations + gear_rotation_members are owner-private end to end: only the
-- owner reads/writes their rotations, and a member INSERT must own BOTH the
-- rotation (owner_id = me) AND the parent gear. Like gear_wear_logs (and unlike
-- run_gear) there is NO public-visibility path.
--
--   1. owner reads only their own rotations + members; a stranger sees none.
--   2. member INSERT requires owning the parent rotation (the rotation gate).
--   3. member INSERT requires owning the parent gear (the gear gate) — blocks
--      slipping another user's gear into your rotation.
--   4. member INSERT as owner of both rotation + gear succeeds.
--   5. a stranger's UPDATE/DELETE against the owner's rotation is RLS-filtered
--      to zero rows (invisible row, no error, no effect).
--   6. deleting the parent gear cascades the membership away; deleting the
--      rotation cascades its members away.
begin;
select plan(12);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('bbbbbbbb-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'owner@rotation.local', '', now(), now()),
  ('bbbbbbbb-0000-0000-0000-0000000000e1', 'authenticated', 'authenticated', 'stranger@rotation.local', '', now(), now());

-- Seed (superuser, RLS bypassed): owner has two shoes, one rotation, one
-- membership. The stranger owns a shoe of their own (for the gear-gate test).
insert into gear (id, owner_id, kind, name)
values
  ('bbbbbbbb-0000-0000-0000-00000000ee01', 'bbbbbbbb-0000-0000-0000-0000000000a1', 'shoe', 'Owner Shoe A'),
  ('bbbbbbbb-0000-0000-0000-00000000ee02', 'bbbbbbbb-0000-0000-0000-0000000000a1', 'shoe', 'Owner Shoe B'),
  ('bbbbbbbb-0000-0000-0000-00000000ee99', 'bbbbbbbb-0000-0000-0000-0000000000e1', 'shoe', 'Stranger Shoe');

insert into gear_rotations (id, owner_id, name)
values
  ('bbbbbbbb-0000-0000-0000-000000aaaa01', 'bbbbbbbb-0000-0000-0000-0000000000a1', 'Daily trainers');

insert into gear_rotation_members (rotation_id, gear_id)
values
  ('bbbbbbbb-0000-0000-0000-000000aaaa01', 'bbbbbbbb-0000-0000-0000-00000000ee01');

set local role authenticated;

-- ============================================================
-- owner-only read (rotation + member)
-- ============================================================
set local "request.jwt.claims" = '{"sub":"bbbbbbbb-0000-0000-0000-0000000000a1","role":"authenticated"}';

select is(
  (select count(*)::int from gear_rotations where owner_id = 'bbbbbbbb-0000-0000-0000-0000000000a1'),
  1, 'owner reads their own rotation');

select is(
  (select count(*)::int from gear_rotation_members where rotation_id = 'bbbbbbbb-0000-0000-0000-000000aaaa01'),
  1, 'owner reads their rotation members');

set local "request.jwt.claims" = '{"sub":"bbbbbbbb-0000-0000-0000-0000000000e1","role":"authenticated"}';

select is(
  (select count(*)::int from gear_rotations where owner_id = 'bbbbbbbb-0000-0000-0000-0000000000a1'),
  0, 'a stranger cannot read another user''s rotation');

select is(
  (select count(*)::int from gear_rotation_members where rotation_id = 'bbbbbbbb-0000-0000-0000-000000aaaa01'),
  0, 'a stranger cannot read another user''s rotation members');

-- ============================================================
-- member INSERT gate: must own the rotation AND the parent gear
-- ============================================================
-- Stranger adds the owner's gear to the owner's rotation → fails the rotation
-- gate (they don't own aaaa01).
select throws_ok(
  $$ insert into gear_rotation_members (rotation_id, gear_id)
       values ('bbbbbbbb-0000-0000-0000-000000aaaa01', 'bbbbbbbb-0000-0000-0000-00000000ee02') $$,
  '42501',
  null,
  'a stranger cannot add members to a rotation they do not own');

-- Owner tries to add the STRANGER's gear to their own rotation → fails the
-- gear gate (they don't own ee99).
set local "request.jwt.claims" = '{"sub":"bbbbbbbb-0000-0000-0000-0000000000a1","role":"authenticated"}';
select throws_ok(
  $$ insert into gear_rotation_members (rotation_id, gear_id)
       values ('bbbbbbbb-0000-0000-0000-000000aaaa01', 'bbbbbbbb-0000-0000-0000-00000000ee99') $$,
  '42501',
  null,
  'owner cannot add another user''s gear to their rotation');

-- Owner adds their OWN second shoe to their OWN rotation → succeeds.
select lives_ok(
  $$ insert into gear_rotation_members (rotation_id, gear_id)
       values ('bbbbbbbb-0000-0000-0000-000000aaaa01', 'bbbbbbbb-0000-0000-0000-00000000ee02') $$,
  'owner can add their own gear to their own rotation');
select is(
  (select count(*)::int from gear_rotation_members where rotation_id = 'bbbbbbbb-0000-0000-0000-000000aaaa01'),
  2, 'owner now sees both members');

-- ============================================================
-- stranger UPDATE/DELETE is RLS-filtered (no error, zero effect)
-- ============================================================
set local "request.jwt.claims" = '{"sub":"bbbbbbbb-0000-0000-0000-0000000000e1","role":"authenticated"}';
select lives_ok(
  $$ update gear_rotations set name = 'hijacked' where id = 'bbbbbbbb-0000-0000-0000-000000aaaa01' $$,
  'a stranger''s rotation update runs but is RLS-filtered');

set local "request.jwt.claims" = '{"sub":"bbbbbbbb-0000-0000-0000-0000000000a1","role":"authenticated"}';
select is(
  (select name from gear_rotations where id = 'bbbbbbbb-0000-0000-0000-000000aaaa01'),
  'Daily trainers', 'the stranger''s update matched no visible row (name unchanged)');

-- ============================================================
-- cascade: deleting a gear removes its membership; deleting the rotation
-- removes all its members
-- ============================================================
delete from gear where id = 'bbbbbbbb-0000-0000-0000-00000000ee01';
select is(
  (select count(*)::int from gear_rotation_members
     where rotation_id = 'bbbbbbbb-0000-0000-0000-000000aaaa01'
       and gear_id = 'bbbbbbbb-0000-0000-0000-00000000ee01'),
  0, 'deleting a gear cascades its rotation membership');

delete from gear_rotations where id = 'bbbbbbbb-0000-0000-0000-000000aaaa01';
select is(
  (select count(*)::int from gear_rotation_members where rotation_id = 'bbbbbbbb-0000-0000-0000-000000aaaa01'),
  0, 'deleting the rotation cascades its remaining members');

select * from finish();
rollback;
