-- RLS suite for `public.club_posts` (the threaded club feed).
--
-- Policy stack (per migrations 20260416_001, 20260417_001 (threaded
-- replies), 20260428_001 (any active member can post)):
--
--   - SELECT "posts readable with their club" — gated on the caller
--     seeing the parent club (public / owner / active member).
--   - INSERT "members can post" — any active member, no parent
--     constraint. This catch-all from 20260428_001 supersedes the
--     two narrower 20260417_001 policies ("admins can post top-
--     level" + "active members can reply"), which are still on the
--     table but are no longer the binding rule. The current
--     effective behaviour is: any active member can post any kind
--     of post (top-level OR reply); only **strangers** and
--     **pending** requesters are blocked. If a future migration
--     tightens this back to admins-only-top-level, this file is
--     where the test will flip — and that's the right shape, because
--     the post creation surface in the web UI assumes the relaxed
--     policy.
--   - DELETE "authors can delete their posts" — `author_id =
--     auth.uid()`. There is no admin-DELETE policy: a club admin
--     who wants to remove a member's post must do so by removing
--     the member (whose row + posts cascade). This is asymmetric
--     with `club_members` where admins CAN delete other members'
--     rows directly.
--
-- Blast radius if INSERT regresses with author_id forge missing:
-- a member writes a post attributed to another user — defamation /
-- harassment shape, plus engagement_chain notifications would
-- mis-route. If DELETE regresses to allow non-author deletion:
-- post-removal becomes a vandalism surface.

begin;

select plan(9);

-- ── Fixture ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000ee0001', 'authenticated', 'authenticated',
   'owner@post.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000ee0002', 'authenticated', 'authenticated',
   'member@post.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000ee0003', 'authenticated', 'authenticated',
   'pending@post.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000ee0004', 'authenticated', 'authenticated',
   'stranger@post.local', '', now(), now());

-- Pre-role-switch fixture (bypasses RLS):
insert into clubs (id, owner_id, name, slug, is_public, join_policy)
values
  ('88888888-8888-8888-8888-888888880001',
   '00000000-0000-0000-0000-000000ee0001',
   'Post Test Club', 'post-test', false, 'request');

insert into club_members (club_id, user_id, role, status)
values
  ('88888888-8888-8888-8888-888888880001',
   '00000000-0000-0000-0000-000000ee0002', 'member', 'active'),
  ('88888888-8888-8888-8888-888888880001',
   '00000000-0000-0000-0000-000000ee0003', 'member', 'pending');

-- Plant a pre-existing top-level post by the owner so SELECT /
-- DELETE tests have something to target.
insert into club_posts (id, club_id, author_id, body)
values
  ('99999999-9999-9999-9999-999999990001',
   '88888888-8888-8888-8888-888888880001',
   '00000000-0000-0000-0000-000000ee0001',
   'Owner top-level post');

set local role authenticated;

-- 1. Active member can SELECT posts in their private club.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ee0002"}';
select results_eq(
  $$ select body from club_posts
     where id = '99999999-9999-9999-9999-999999990001' $$,
  $$ values ('Owner top-level post'::text) $$,
  'active member can SELECT posts in their private club'
);

-- 2. Stranger cannot SELECT posts in a private club they do not
--    belong to.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ee0004"}';
select is_empty(
  $$ select id from club_posts
     where club_id = '88888888-8888-8888-8888-888888880001' $$,
  'stranger cannot SELECT posts in a private club they do not belong to'
);

-- 3. Active member can INSERT a top-level post. The
--    20260428_001 catch-all "members can post" makes this work
--    despite the older "admins can post top-level" policy still
--    being on the table.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ee0002"}';
insert into club_posts (id, club_id, author_id, body)
values
  ('99999999-9999-9999-9999-999999990002',
   '88888888-8888-8888-8888-888888880001',
   '00000000-0000-0000-0000-000000ee0002',
   'Member top-level post');
select results_eq(
  $$ select count(*)::int from club_posts
     where id = '99999999-9999-9999-9999-999999990002' $$,
  $$ values (1) $$,
  'active member can INSERT a top-level post (20260428_001 catch-all)'
);

-- 4. Active member can INSERT a reply (parent_post_id set).
insert into club_posts (id, club_id, author_id, body, parent_post_id)
values
  ('99999999-9999-9999-9999-999999990003',
   '88888888-8888-8888-8888-888888880001',
   '00000000-0000-0000-0000-000000ee0002',
   'Reply to owner',
   '99999999-9999-9999-9999-999999990001');
select results_eq(
  $$ select count(*)::int from club_posts
     where id = '99999999-9999-9999-9999-999999990003' $$,
  $$ values (1) $$,
  'active member can INSERT a reply post'
);

-- 5. Stranger INSERT rejected (not an active member of any club).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ee0004"}';
select throws_ok(
  $$ insert into club_posts (club_id, author_id, body)
       values ('88888888-8888-8888-8888-888888880001',
               '00000000-0000-0000-0000-000000ee0004',
               'Spam from stranger') $$,
  '42501',
  null,
  'stranger cannot INSERT a post in a club they do not belong to'
);

-- 6. Pending requester INSERT rejected (`is_club_member` excludes
--    pending status — this is the load-bearing exclusion that
--    keeps pending requests from gaining write access).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ee0003"}';
select throws_ok(
  $$ insert into club_posts (club_id, author_id, body)
       values ('88888888-8888-8888-8888-888888880001',
               '00000000-0000-0000-0000-000000ee0003',
               'Premature post from pending') $$,
  '42501',
  null,
  'pending requester cannot INSERT a post (is_club_member excludes pending)'
);

-- 7. Forged author_id INSERT rejected. The shape of the catch-all
--    `with check (is_club_member(club_id) and author_id = auth.uid())`
--    enforces both branches.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ee0002"}';
select throws_ok(
  $$ insert into club_posts (club_id, author_id, body)
       values ('88888888-8888-8888-8888-888888880001',
               '00000000-0000-0000-0000-000000ee0001',
               'Defamation under owner''s name') $$,
  '42501',
  null,
  'cannot INSERT a post under another user_id'
);

-- 8. Author can DELETE their own post.
delete from club_posts
  where id = '99999999-9999-9999-9999-999999990002';
select is_empty(
  $$ select id from club_posts
     where id = '99999999-9999-9999-9999-999999990002' $$,
  'author can DELETE their own post'
);

-- 9. Non-author (even a co-member, even an admin) DELETE is a
--    silent no-op. There is no admin-DELETE policy on club_posts.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ee0001"}';
delete from club_posts
  where id = '99999999-9999-9999-9999-999999990003';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ee0002"}';
select results_eq(
  $$ select count(*)::int from club_posts
     where id = '99999999-9999-9999-9999-999999990003' $$,
  $$ values (1) $$,
  'club owner (non-author) DELETE on a member post is a no-op (no admin-DELETE policy)'
);

select * from finish();

rollback;
