-- Challenge discovery (challenges.md; migration 20270308_001). Proves:
--   * participant_count is a trigger-maintained cache == count(*)
--   * browse_public_challenges ranks by popularity (size + 7-day join velocity)
--   * it excludes joined / ended / private boards and suppresses dead ones
--   * search + pagination
--   * the create-challenge rate limit fires past the per-window cap
--
-- All challenges are inserted as the (superuser) test role, so auth.uid() is
-- null at insert time and the create rate-limit trigger is bypassed for setup —
-- exactly the seed/service path. We set request.jwt.claims per assertion so the
-- SECURITY DEFINER RPC sees a caller.

begin;

select plan(12);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000bb000001', 'authenticated', 'authenticated', 'x@bb.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000bb000002', 'authenticated', 'authenticated', 'u1@bb.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000bb000003', 'authenticated', 'authenticated', 'u2@bb.local', '', now(), now());

insert into user_profiles (id, display_name) values
  ('00000000-0000-0000-0000-0000bb000001', 'Xavier'),
  ('00000000-0000-0000-0000-0000bb000002', 'Uno'),
  ('00000000-0000-0000-0000-0000bb000003', 'Dos')
on conflict (id) do nothing;

-- POP: 2 participants, both joined now → highest score. (unique search token)
-- MID: 1 participant joined now.
-- OLDJOIN: 2 participants joined 30 days ago → velocity 0, ranks below MID.
-- JOINED: caller Xavier is a participant → must be excluded from Browse.
-- PRIVATE: is_public=false → excluded.
-- ENDED: window already closed → excluded.
-- DEAD: 0 participants, created 10 days ago, not caller's → suppressed.
-- NEWEMPTY: 0 participants but created now → shown (grace window).
-- TRIG: 0 participants, created 10 days ago → suppressed; used for the trigger test.
insert into challenges (id, creator_id, title, metric, scope, goal_value, starts_at, ends_at, is_public, created_at) values
  ('bbbb0001-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000bb000002',
   'Zephyrhunt POP', 'distance', 'individual', 100000, now() - interval '5 days', now() + interval '20 days', true, now()),
  ('bbbb0002-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000bb000002',
   'MID board', 'distance', 'individual', 100000, now() - interval '5 days', now() + interval '10 days', true, now()),
  ('bbbb0003-0000-0000-0000-000000000003', '00000000-0000-0000-0000-0000bb000002',
   'OLDJOIN board', 'distance', 'individual', 100000, now() - interval '35 days', now() + interval '25 days', true, now()),
  ('bbbb0004-0000-0000-0000-000000000004', '00000000-0000-0000-0000-0000bb000002',
   'JOINED board', 'distance', 'individual', 100000, now() - interval '5 days', now() + interval '20 days', true, now()),
  ('bbbb0005-0000-0000-0000-000000000005', '00000000-0000-0000-0000-0000bb000002',
   'PRIVATE board', 'distance', 'individual', 100000, now() - interval '5 days', now() + interval '20 days', false, now()),
  ('bbbb0006-0000-0000-0000-000000000006', '00000000-0000-0000-0000-0000bb000002',
   'ENDED board', 'distance', 'individual', 100000, now() - interval '40 days', now() - interval '1 day', true, now()),
  ('bbbb0007-0000-0000-0000-000000000007', '00000000-0000-0000-0000-0000bb000002',
   'DEAD board', 'distance', 'individual', 100000, now() - interval '10 days', now() + interval '20 days', true, now() - interval '10 days'),
  ('bbbb0008-0000-0000-0000-000000000008', '00000000-0000-0000-0000-0000bb000002',
   'NEWEMPTY board', 'distance', 'individual', 100000, now() - interval '1 day', now() + interval '12 days', true, now()),
  ('bbbb0009-0000-0000-0000-000000000009', '00000000-0000-0000-0000-0000bb000002',
   'TRIG board', 'distance', 'individual', 100000, now() - interval '10 days', now() + interval '20 days', true, now() - interval '10 days');

-- Recent joins (default joined_at = now()).
insert into challenge_participants (challenge_id, user_id) values
  ('bbbb0001-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000bb000002'),
  ('bbbb0001-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000bb000003'),
  ('bbbb0002-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000bb000002'),
  ('bbbb0004-0000-0000-0000-000000000004', '00000000-0000-0000-0000-0000bb000001');

-- Stale joins (30 days ago → outside the 7-day velocity window).
insert into challenge_participants (challenge_id, user_id, joined_at) values
  ('bbbb0003-0000-0000-0000-000000000003', '00000000-0000-0000-0000-0000bb000002', now() - interval '30 days'),
  ('bbbb0003-0000-0000-0000-000000000003', '00000000-0000-0000-0000-0000bb000003', now() - interval '30 days');

-- ── 1. participant_count cache == count(*) (trigger maintained on insert) ──
select is(
  (select participant_count from challenges where id = 'bbbb0001-0000-0000-0000-000000000001'),
  2, 'participant_count cache reflects the two inserted participants');

-- ── Browse as Xavier ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000bb000001","role":"authenticated"}';

-- ── 2. popularity ordering + every exclusion/suppression ──
-- The DB is seeded, so other public challenges coexist. Scope to this test's
-- fixtures; the RPC returns global score order, so the fixtures' RELATIVE order
-- is preserved, and the excluded/suppressed ones simply never appear.
select results_eq(
  $$ select title from browse_public_challenges(null, 200, 0)
     where title in ('Zephyrhunt POP', 'MID board', 'OLDJOIN board', 'NEWEMPTY board',
                     'JOINED board', 'PRIVATE board', 'ENDED board', 'DEAD board') $$,
  $$ values ('Zephyrhunt POP'), ('MID board'), ('OLDJOIN board'), ('NEWEMPTY board') $$,
  'Browse: score order POP>MID>OLDJOIN>NEWEMPTY; joined/private/ended excluded, dead suppressed');

-- ── 3-6. targeted exclusion assertions (clear failure messages) ──
select is(
  (select count(*)::int from browse_public_challenges(null, 24, 0) where title = 'JOINED board'),
  0, 'a challenge the caller joined is excluded from Browse');
select is(
  (select count(*)::int from browse_public_challenges(null, 24, 0) where title = 'PRIVATE board'),
  0, 'a private challenge is excluded from Browse');
select is(
  (select count(*)::int from browse_public_challenges(null, 24, 0) where title = 'ENDED board'),
  0, 'an ended challenge is excluded from Browse');
select is(
  (select count(*)::int from browse_public_challenges(null, 24, 0) where title = 'DEAD board'),
  0, 'a participant-less board past the grace window is suppressed');

-- ── 7. search filters by title substring ──
select results_eq(
  $$ select title from browse_public_challenges('Zephyr', 24, 0) $$,
  $$ values ('Zephyrhunt POP') $$,
  'search narrows Browse to the matching title');

-- ── 8-9. pagination: limit caps the page; offset advances without overlap ──
-- (Seed-independent: only relies on >= 6 eligible public challenges existing.)
select is(
  (select count(*)::int from browse_public_challenges(null, 3, 0)),
  3, 'limit caps the page size');
select is(
  (select count(*)::int from (
     select id from browse_public_challenges(null, 3, 0)
     intersect
     select id from browse_public_challenges(null, 3, 3)
   ) s),
  0, 'offset advances to a non-overlapping next page');

-- ── 9-10. trigger keeps the cache correct on join + leave ──
insert into challenge_participants (challenge_id, user_id)
  values ('bbbb0009-0000-0000-0000-000000000009', '00000000-0000-0000-0000-0000bb000003');
select is(
  (select participant_count from challenges where id = 'bbbb0009-0000-0000-0000-000000000009'),
  1, 'joining increments participant_count via trigger');
delete from challenge_participants
  where challenge_id = 'bbbb0009-0000-0000-0000-000000000009' and user_id = '00000000-0000-0000-0000-0000bb000003';
select is(
  (select participant_count from challenges where id = 'bbbb0009-0000-0000-0000-000000000009'),
  0, 'leaving decrements participant_count via trigger');

-- ── 11. create rate limit fires past the per-window cap (30/hour) ──
-- Xavier's create_challenge bucket is clean (setup inserts were auth-less). Fill
-- it to the cap, then the next create must raise.
insert into challenges (id, creator_id, title, metric, scope, starts_at, ends_at)
  select gen_random_uuid(), '00000000-0000-0000-0000-0000bb000001', 'rl ' || g,
         'distance', 'individual', now(), now() + interval '10 days'
  from generate_series(1, 30) g;
select throws_ok(
  $$ insert into challenges (id, creator_id, title, metric, scope, starts_at, ends_at)
     values (gen_random_uuid(), '00000000-0000-0000-0000-0000bb000001', 'rl over',
             'distance', 'individual', now(), now() + interval '10 days') $$,
  'challenge_create_rate_limited',
  'the 31st create in the window is rate-limited');

select * from finish();

rollback;
