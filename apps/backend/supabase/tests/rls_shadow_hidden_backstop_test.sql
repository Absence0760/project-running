-- RLS backstop for shadow_hidden on clubs + events (migration
-- 20270328_001). A moderation auto-hidden (shadow_hidden) club must drop
-- out of every anon/non-member read of the BASE tables — not just the
-- surfaces that remember to add the filter — while its owner + active
-- members keep visibility (soft-hide pending review, not a deletion).
--
-- Companion to rls_clubs_test.sql / rls_events_test.sql (which cover the
-- is_public visibility matrix) and public_helpers_shadow_hidden_test.sql
-- (which covers the is_public_*_by_id definers).

begin;

select plan(7);

-- ── Fixture (runs as the test-runner role → bypasses RLS) ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000d0001', 'authenticated', 'authenticated',
   'owner@hide.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000d0002', 'authenticated', 'authenticated',
   'member@hide.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000d0003', 'authenticated', 'authenticated',
   'stranger@hide.local', '', now(), now());

-- A PUBLIC club (so, pre-hide, anon can see it) owned by d0001. The
-- enroll_club_owner trigger auto-enrolls the owner as a member.
insert into clubs (id, owner_id, name, slug, is_public, shadow_hidden)
values
  ('77777777-7777-7777-7777-777777770001',
   '00000000-0000-0000-0000-0000000d0001',
   'Hidden Harriers', 'hidden-harriers', true, false);

insert into club_members (club_id, user_id, role, status)
values
  ('77777777-7777-7777-7777-777777770001',
   '00000000-0000-0000-0000-0000000d0002', 'member', 'active');

-- A PUBLIC event under the club (event-level is_public = true so anon can
-- see it pre-hide via the events policy's second clause).
insert into events (id, club_id, title, starts_at, author_id, is_public)
values
  ('88888888-8888-8888-8888-888888880001',
   '77777777-7777-7777-7777-777777770001',
   'Hidden Long Run', now() + interval '1 day',
   '00000000-0000-0000-0000-0000000d0001', true);

-- Shadow-hide the club.
update clubs set shadow_hidden = true
  where id = '77777777-7777-7777-7777-777777770001';

-- ── anon: hidden club + its events are invisible ──
set local role anon;
select is_empty(
  $$ select slug from clubs where id = '77777777-7777-7777-7777-777777770001' $$,
  'anon cannot SELECT a shadow-hidden public club'
);
select is_empty(
  $$ select id from events where id = '88888888-8888-8888-8888-888888880001' $$,
  'anon cannot SELECT an event under a shadow-hidden club'
);
reset role;

-- ── authenticated non-member: also invisible ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000d0003"}';
select is_empty(
  $$ select slug from clubs where id = '77777777-7777-7777-7777-777777770001' $$,
  'a non-member cannot SELECT a shadow-hidden public club'
);
select is_empty(
  $$ select id from events where id = '88888888-8888-8888-8888-888888880001' $$,
  'a non-member cannot SELECT an event under a shadow-hidden club'
);

-- ── owner still sees their hidden club + its events ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000d0001"}';
select results_eq(
  $$ select slug from clubs where id = '77777777-7777-7777-7777-777777770001' $$,
  $$ values ('hidden-harriers'::text) $$,
  'owner still SELECTs their own shadow-hidden club'
);
select results_eq(
  $$ select title from events where id = '88888888-8888-8888-8888-888888880001' $$,
  $$ values ('Hidden Long Run'::text) $$,
  'owner still SELECTs an event under their shadow-hidden club'
);

-- ── active member still sees the hidden club ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000d0002"}';
select results_eq(
  $$ select slug from clubs where id = '77777777-7777-7777-7777-777777770001' $$,
  $$ values ('hidden-harriers'::text) $$,
  'active member still SELECTs the shadow-hidden club'
);

select finish();
rollback;
