-- RLS suite for `public.clubs` base policies.
--
-- Companion file. `rls_clubs_invite_token_lockdown_test.sql` already
-- pins the column-grant + `get_club_invite_token` rotation surface
-- from migrations `20260801_001` + `20260818_001`. This file covers
-- the row-level policies that govern who can see / create / update /
-- delete a club row.
--
-- Policy stack (per migrations 20260416_001 + 20260417_001):
--   - SELECT "public clubs are readable by anyone" — `is_public = true`.
--   - SELECT "private clubs are readable by members" — owner OR
--     `is_club_member(id)` (active membership only — pending rows
--     don't grant visibility, see 20260417_001).
--   - INSERT "authenticated users can create clubs" — caller is
--     `owner_id`. The `enroll_club_owner` AFTER trigger auto-inserts
--     a matching `club_members` row with role `owner`.
--   - UPDATE "club admins can update their club" — `is_club_admin(id)`
--     (owner OR admin role on active membership).
--   - DELETE "club owner can delete their club" — `owner_id = auth.uid()`
--     ONLY. Note the asymmetry: admins can UPDATE but not DELETE; only
--     the original creator can wipe the club. A regression that
--     widens DELETE to admins would let a malicious co-admin nuke a
--     club + cascade every member / event / post / club_owned route.
--
-- Blast radius if SELECT regresses: private clubs become enumerable
-- (member roster + posts + events all hang off club visibility). If
-- INSERT regresses with owner_id forge: an attacker plants a club
-- under another user_id, the trigger enrolls THAT user as owner, and
-- the trigger-installed owner row now grants the planted user
-- elevated privileges over a club they did not create.

begin;

select plan(9);

-- ── Fixture ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000cc0001', 'authenticated', 'authenticated',
   'owner@club.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000cc0002', 'authenticated', 'authenticated',
   'admin@club.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000cc0003', 'authenticated', 'authenticated',
   'member@club.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000cc0004', 'authenticated', 'authenticated',
   'stranger@club.local', '', now(), now());

-- Fixture setup runs as the implicit test-runner role (no `set local
-- role authenticated` yet), which bypasses RLS — this is how the
-- other RLS suites plant cross-user state. The owner's auto-enrolled
-- `club_members` row is installed by the `enroll_club_owner` trigger
-- (SECURITY DEFINER, fires regardless of caller role).
insert into clubs (id, owner_id, name, slug, is_public)
values
  ('66666666-6666-6666-6666-666666660001',
   '00000000-0000-0000-0000-000000cc0001',
   'Public Striders', 'public-striders', true),
  ('66666666-6666-6666-6666-666666660002',
   '00000000-0000-0000-0000-000000cc0001',
   'Private Striders', 'private-striders', false);

-- Plant cc0002 as an admin of the private club and cc0003 as a
-- plain member. Pre-role-switch INSERT bypasses RLS so we don't
-- need to thread the rows through join_club_by_token.
insert into club_members (club_id, user_id, role, status)
values
  ('66666666-6666-6666-6666-666666660002',
   '00000000-0000-0000-0000-000000cc0002', 'admin', 'active'),
  ('66666666-6666-6666-6666-666666660002',
   '00000000-0000-0000-0000-000000cc0003', 'member', 'active');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000cc0001"}';

-- 1. Owner can SELECT their own private club.
select results_eq(
  $$ select slug from clubs
     where id = '66666666-6666-6666-6666-666666660002' $$,
  $$ values ('private-striders'::text) $$,
  'owner can SELECT their own private club'
);

-- 2. Member (active, non-owner) can SELECT the private club via
--    `is_club_member` branch.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000cc0003"}';
select results_eq(
  $$ select slug from clubs
     where id = '66666666-6666-6666-6666-666666660002' $$,
  $$ values ('private-striders'::text) $$,
  'active member can SELECT their private club'
);

-- 3. Stranger can SELECT the public club but NOT the private one.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000cc0004"}';
select results_eq(
  $$ select slug from clubs
     where id in (
       '66666666-6666-6666-6666-666666660001',
       '66666666-6666-6666-6666-666666660002') order by slug $$,
  $$ values ('public-striders'::text) $$,
  'stranger sees only the public club, never the private one'
);

-- 4. Forged INSERT under another owner_id is rejected.
select throws_ok(
  $$ insert into clubs (owner_id, name, slug)
       values ('00000000-0000-0000-0000-000000cc0001',
               'Pwned', 'pwned-club') $$,
  '42501',
  null,
  'cannot INSERT a club under another user_id (and trigger-elevate the victim)'
);

-- 5. Admin (non-owner) can UPDATE the club name.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000cc0002"}';
update clubs set name = 'Edited By Admin'
  where id = '66666666-6666-6666-6666-666666660002';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000cc0001"}';
select results_eq(
  $$ select name from clubs
     where id = '66666666-6666-6666-6666-666666660002' $$,
  $$ values ('Edited By Admin'::text) $$,
  'admin (non-owner) can UPDATE their club via is_club_admin'
);

-- 6. Plain member UPDATE is a silent no-op (is_club_admin fails for
--    role='member').
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000cc0003"}';
update clubs set name = 'Pwned By Member'
  where id = '66666666-6666-6666-6666-666666660002';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000cc0001"}';
select results_eq(
  $$ select name from clubs
     where id = '66666666-6666-6666-6666-666666660002' $$,
  $$ values ('Edited By Admin'::text) $$,
  'plain member UPDATE on a club is a no-op'
);

-- 7. Admin (non-owner) DELETE is a silent no-op. The asymmetry —
--    admins UPDATE, only the owner DELETEs — is the load-bearing
--    invariant here.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000cc0002"}';
delete from clubs where id = '66666666-6666-6666-6666-666666660002';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000cc0001"}';
select results_eq(
  $$ select count(*)::int from clubs
     where id = '66666666-6666-6666-6666-666666660002' $$,
  $$ values (1) $$,
  'admin (non-owner) cannot DELETE a club — owner-only by policy'
);

-- 8. Stranger DELETE is a silent no-op.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000cc0004"}';
delete from clubs where id = '66666666-6666-6666-6666-666666660001';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000cc0001"}';
select results_eq(
  $$ select count(*)::int from clubs
     where id = '66666666-6666-6666-6666-666666660001' $$,
  $$ values (1) $$,
  'stranger cannot DELETE a club'
);

-- 9. Owner CAN DELETE their own club (positive control on the
--    owner-only DELETE policy).
update club_members
  set status = 'inactive'
  where club_id = '66666666-6666-6666-6666-666666660001';
-- ↑ avoid the auto-enrolled owner row tripping the cascade
delete from clubs where id = '66666666-6666-6666-6666-666666660001';
select is_empty(
  $$ select id from clubs
     where id = '66666666-6666-6666-6666-666666660001' $$,
  'owner can DELETE their own club (positive control)'
);

select * from finish();

rollback;
