-- RLS suite for `public.club_members`.
--
-- Policy stack (per migrations 20260416_001, 20260417_001 (active /
-- pending status), 20260702_001 (join-policy gate)):
--   - SELECT "users can see their own membership" — own row, any
--     status. Required so a pending requester can poll their own
--     status without being able to read the rest of the roster.
--   - SELECT "members readable with their club" — gated on the
--     caller seeing the parent club (public / owner / active member).
--   - INSERT "self-join open clubs" — caller=user_id, role='member',
--     status='active', `clubs.join_policy = 'open'`. The role pin
--     stops self-joiners claiming admin / owner / event_organiser /
--     race_director.
--   - INSERT "self-request join request-policy clubs" — same shape
--     with status='pending' and `join_policy = 'request'`.
--   - UPDATE "admins can change roles" — `is_club_admin`.
--   - DELETE "users can leave clubs" — own row.
--   - DELETE "admins can manage members" — `is_club_admin`.
--
-- Invite-policy clubs are deliberately uncovered by the INSERT
-- policies — admission only via the `join_club_by_token` SECURITY
-- DEFINER RPC (20260417_001).
--
-- Blast radius if INSERT regresses with the role pin missing: a
-- self-joiner claims 'admin' and instantly gains UPDATE / DELETE
-- authority over every other member's row + the club itself.

begin;

select plan(10);

-- ── Fixture ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000dd0001', 'authenticated', 'authenticated',
   'owner@member.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000dd0002', 'authenticated', 'authenticated',
   'admin@member.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000dd0003', 'authenticated', 'authenticated',
   'member@member.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000dd0004', 'authenticated', 'authenticated',
   'pending@member.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000dd0005', 'authenticated', 'authenticated',
   'stranger@member.local', '', now(), now());

-- Setup as the implicit test-runner role (RLS bypassed) so we can
-- plant cross-user state. dd0001 owns one open public club, one
-- private request-policy club, and one invite-only club.
insert into clubs (id, owner_id, name, slug, is_public, join_policy)
values
  ('77777777-7777-7777-7777-777777770001',
   '00000000-0000-0000-0000-000000dd0001',
   'Open Public', 'open-public', true, 'open'),
  ('77777777-7777-7777-7777-777777770002',
   '00000000-0000-0000-0000-000000dd0001',
   'Private Request', 'private-request', false, 'request'),
  ('77777777-7777-7777-7777-777777770003',
   '00000000-0000-0000-0000-000000dd0001',
   'Private Invite', 'private-invite', false, 'invite');

-- dd0002 → admin of the private request-policy club.
-- dd0003 → active member.
-- dd0004 → pending member.
insert into club_members (club_id, user_id, role, status)
values
  ('77777777-7777-7777-7777-777777770002',
   '00000000-0000-0000-0000-000000dd0002', 'admin', 'active'),
  ('77777777-7777-7777-7777-777777770002',
   '00000000-0000-0000-0000-000000dd0003', 'member', 'active'),
  ('77777777-7777-7777-7777-777777770002',
   '00000000-0000-0000-0000-000000dd0004', 'member', 'pending');

set local role authenticated;

-- 1. Pending requester can SELECT their own membership row even
--    though `is_club_member` excludes pending status. The dedicated
--    own-row SELECT policy from 20260417_001 makes this possible —
--    needed so the UI can render "Request pending" without leaking
--    the rest of the roster.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000dd0004"}';
select results_eq(
  $$ select status from club_members
     where club_id = '77777777-7777-7777-7777-777777770002'
       and user_id = '00000000-0000-0000-0000-000000dd0004' $$,
  $$ values ('pending'::text) $$,
  'pending user can SELECT their own membership row'
);

-- 2. Active member can SELECT the full roster of their private
--    club (the "members readable with their club" branch fires
--    because is_club_member returns true for them).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000dd0003"}';
select results_eq(
  $$ select count(*)::int from club_members
     where club_id = '77777777-7777-7777-7777-777777770002' $$,
  $$ values (4) $$,
  'active member can SELECT the full roster of their private club (owner + admin + member + pending)'
);

-- 3. Stranger cannot SELECT any roster row of a private club —
--    neither their own (no row exists) nor anyone else's.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000dd0005"}';
select is_empty(
  $$ select user_id from club_members
     where club_id = '77777777-7777-7777-7777-777777770002' $$,
  'stranger cannot SELECT the roster of a private club they do not belong to'
);

-- 4. Self-join the open public club as `member` / `active` works
--    (positive control on the open-join policy).
insert into club_members (club_id, user_id, role, status)
values
  ('77777777-7777-7777-7777-777777770001',
   '00000000-0000-0000-0000-000000dd0005', 'member', 'active');
select results_eq(
  $$ select role from club_members
     where club_id = '77777777-7777-7777-7777-777777770001'
       and user_id = '00000000-0000-0000-0000-000000dd0005' $$,
  $$ values ('member'::text) $$,
  'self-join an open club as member / active works (positive)'
);

-- 5. Self-join with role='admin' is rejected. Closes the privilege-
--    escalation hole that the 20260702_001 join-policy gate landed
--    to fix — without the `role = 'member'` pin, a self-joiner
--    could claim any of admin / owner / event_organiser /
--    race_director.
select throws_ok(
  $$ insert into club_members (club_id, user_id, role, status)
       values ('77777777-7777-7777-7777-777777770001',
               '00000000-0000-0000-0000-000000dd0005',
               'admin', 'active') $$,
  '42501',
  null,
  'cannot self-join an open club as admin (role pin closes escalation)'
);

-- 6. Self-join a request-policy club with status='active' is
--    rejected — only pending is allowed via the request path; the
--    admin must approve.
select throws_ok(
  $$ insert into club_members (club_id, user_id, role, status)
       values ('77777777-7777-7777-7777-777777770002',
               '00000000-0000-0000-0000-000000dd0005',
               'member', 'active') $$,
  '42501',
  null,
  'cannot self-join a request-policy club as active (must be pending)'
);

-- 7. Forged user_id INSERT (planting a membership for another user)
--    is rejected.
select throws_ok(
  $$ insert into club_members (club_id, user_id, role, status)
       values ('77777777-7777-7777-7777-777777770001',
               '00000000-0000-0000-0000-000000dd0001',
               'member', 'active') $$,
  '42501',
  null,
  'cannot INSERT a club_members row under another user_id'
);

-- 8. Admin can UPDATE another member's role (promote / demote).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000dd0002"}';
update club_members
  set role = 'event_organiser'
  where club_id = '77777777-7777-7777-7777-777777770002'
    and user_id = '00000000-0000-0000-0000-000000dd0003';
select results_eq(
  $$ select role from club_members
     where club_id = '77777777-7777-7777-7777-777777770002'
       and user_id = '00000000-0000-0000-0000-000000dd0003' $$,
  $$ values ('event_organiser'::text) $$,
  'admin can UPDATE another member''s role'
);

-- 9. Plain member cannot UPDATE another row (silent no-op).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000dd0003"}';
update club_members
  set role = 'admin'
  where club_id = '77777777-7777-7777-7777-777777770002'
    and user_id = '00000000-0000-0000-0000-000000dd0004';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000dd0001"}';
select results_eq(
  $$ select role from club_members
     where club_id = '77777777-7777-7777-7777-777777770002'
       and user_id = '00000000-0000-0000-0000-000000dd0004' $$,
  $$ values ('member'::text) $$,
  'plain member UPDATE on another user''s row is a no-op (self-promote blocked)'
);

-- 10. User can DELETE their own membership (leave club).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000dd0003"}';
delete from club_members
  where club_id = '77777777-7777-7777-7777-777777770002'
    and user_id = '00000000-0000-0000-0000-000000dd0003';
select is_empty(
  $$ select user_id from club_members
     where club_id = '77777777-7777-7777-7777-777777770002'
       and user_id = '00000000-0000-0000-0000-000000dd0003' $$,
  'user can DELETE their own membership row (leave club)'
);

select * from finish();

rollback;
