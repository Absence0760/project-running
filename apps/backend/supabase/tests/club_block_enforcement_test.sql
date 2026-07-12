-- Block enforcement inside a shared club — roster + post feed.
--
-- Pins the fix in 20270402_001. Before it, the club_members and
-- club_posts SELECT policies gated purely on shared club membership,
-- so a blocked user stayed fully visible in the roster and the post
-- feed of any club both parties belong to — a block bypass. Every
-- other social read path carries `is_blocked_either_way`; these two
-- now do too.
--
-- Fixture: one PUBLIC club owned by A (auto-enrolled as an active
-- owner member via enroll_club_owner_trigger). B and C are active
-- members. A blocks B. C blocks nobody. Each of A / B / C has one
-- top-level post. The block is symmetric, so A and B must be hidden
-- from each other in BOTH surfaces, while non-blocked C stays visible
-- to everyone and each caller always sees their OWN rows.

begin;

select plan(11);

-- ── Fixture (RLS bypassed as the implicit test-runner role) ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000cb001', 'authenticated', 'authenticated',
   'a@block.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000cb002', 'authenticated', 'authenticated',
   'b@block.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000cb003', 'authenticated', 'authenticated',
   'c@block.local', '', now(), now());

-- Public club owned by A → enroll_club_owner_trigger plants A's
-- active owner membership row automatically.
insert into clubs (id, owner_id, name, slug, is_public, join_policy)
values
  ('cbcbcbcb-cbcb-cbcb-cbcb-cbcbcbcbcb01',
   '00000000-0000-0000-0000-0000000cb001',
   'Block Club', 'block-club', true, 'open');

insert into club_members (club_id, user_id, role, status)
values
  ('cbcbcbcb-cbcb-cbcb-cbcb-cbcbcbcbcb01',
   '00000000-0000-0000-0000-0000000cb002', 'member', 'active'),
  ('cbcbcbcb-cbcb-cbcb-cbcb-cbcbcbcbcb01',
   '00000000-0000-0000-0000-0000000cb003', 'member', 'active');

-- One post each so the feed has a per-author target.
insert into club_posts (id, club_id, author_id, body)
values
  ('dddddddd-dddd-dddd-dddd-ddddddddcb0a',
   'cbcbcbcb-cbcb-cbcb-cbcb-cbcbcbcbcb01',
   '00000000-0000-0000-0000-0000000cb001', 'A post'),
  ('dddddddd-dddd-dddd-dddd-ddddddddcb0b',
   'cbcbcbcb-cbcb-cbcb-cbcb-cbcbcbcbcb01',
   '00000000-0000-0000-0000-0000000cb002', 'B post'),
  ('dddddddd-dddd-dddd-dddd-ddddddddcb0c',
   'cbcbcbcb-cbcb-cbcb-cbcb-cbcbcbcbcb01',
   '00000000-0000-0000-0000-0000000cb003', 'C post');

-- A blocks B (symmetric via is_blocked_either_way).
insert into user_blocks (blocker_id, blocked_id)
values
  ('00000000-0000-0000-0000-0000000cb001',
   '00000000-0000-0000-0000-0000000cb002');

set local role authenticated;

-- ── Roster (club_members) ──

-- 1. Control: C blocks nobody → sees the full 3-member active roster.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cb003"}';
select results_eq(
  $$ select count(*)::int from club_members
     where club_id = 'cbcbcbcb-cbcb-cbcb-cbcb-cbcbcbcbcb01'
       and status = 'active' $$,
  $$ values (3) $$,
  'non-blocking member C sees the full active roster (A + B + C)'
);

-- 2. A sees the roster WITHOUT the blocked B — A + C only.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cb001"}';
select results_eq(
  $$ select count(*)::int from club_members
     where club_id = 'cbcbcbcb-cbcb-cbcb-cbcb-cbcbcbcbcb01'
       and status = 'active' $$,
  $$ values (2) $$,
  'A sees only 2 active roster rows (blocked B hidden)'
);

-- 3. A cannot see B's specific roster row.
select is_empty(
  $$ select user_id from club_members
     where club_id = 'cbcbcbcb-cbcb-cbcb-cbcb-cbcbcbcbcb01'
       and user_id = '00000000-0000-0000-0000-0000000cb002' $$,
  'A cannot SELECT blocked B''s club_members row'
);

-- 4. A still sees her OWN roster row (self is never hidden).
select results_eq(
  $$ select role from club_members
     where club_id = 'cbcbcbcb-cbcb-cbcb-cbcb-cbcbcbcbcb01'
       and user_id = '00000000-0000-0000-0000-0000000cb001' $$,
  $$ values ('owner'::text) $$,
  'A still sees her own membership row'
);

-- 5. A still sees non-blocked C's roster row.
select isnt_empty(
  $$ select user_id from club_members
     where club_id = 'cbcbcbcb-cbcb-cbcb-cbcb-cbcbcbcbcb01'
       and user_id = '00000000-0000-0000-0000-0000000cb003' $$,
  'A still sees non-blocked member C''s roster row'
);

-- 6. Symmetric: B cannot see A's roster row either.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cb002"}';
select is_empty(
  $$ select user_id from club_members
     where club_id = 'cbcbcbcb-cbcb-cbcb-cbcb-cbcbcbcbcb01'
       and user_id = '00000000-0000-0000-0000-0000000cb001' $$,
  'B cannot SELECT A''s club_members row (block is symmetric)'
);

-- ── Feed (club_posts) ──

-- 7. Control: C sees all 3 posts.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cb003"}';
select results_eq(
  $$ select count(*)::int from club_posts
     where club_id = 'cbcbcbcb-cbcb-cbcb-cbcb-cbcbcbcbcb01' $$,
  $$ values (3) $$,
  'non-blocking member C sees all 3 club posts'
);

-- 8. A cannot see blocked B's post.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cb001"}';
select is_empty(
  $$ select id from club_posts
     where id = 'dddddddd-dddd-dddd-dddd-ddddddddcb0b' $$,
  'A cannot SELECT blocked B''s club_post'
);

-- 9. A still sees non-blocked C's post + her own — 2 of 3.
select results_eq(
  $$ select count(*)::int from club_posts
     where club_id = 'cbcbcbcb-cbcb-cbcb-cbcb-cbcbcbcbcb01' $$,
  $$ values (2) $$,
  'A sees only 2 posts (her own + C''s; blocked B''s hidden)'
);

-- 10. A still sees her OWN post (self is never hidden).
select isnt_empty(
  $$ select id from club_posts
     where id = 'dddddddd-dddd-dddd-dddd-ddddddddcb0a' $$,
  'A still sees her own club_post'
);

-- 11. Symmetric: B cannot see A's post.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cb002"}';
select is_empty(
  $$ select id from club_posts
     where id = 'dddddddd-dddd-dddd-dddd-ddddddddcb0a' $$,
  'B cannot SELECT A''s club_post (block is symmetric)'
);

select * from finish();

rollback;
