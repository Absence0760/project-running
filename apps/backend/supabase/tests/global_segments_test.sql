-- pgtap suite for the global / famous-segment catalogue (20270411_001).
--
-- Covers:
--   * public-read: anyone (anon + authenticated) sees ACTIVE catalogue
--     segments; inactive rows are hidden.
--   * curator gate: a non-admin cannot INSERT/UPDATE/DELETE a catalogue
--     segment; an admin (app_admins allow-list) can.
--   * effort privacy: a private run's effort never leaks to a stranger
--     through the base table (private.is_run_visible_to gate).
--   * effort insert: run owner inserts on own runs only; no third-party
--     writes on someone else's run.
--   * leaderboard: authenticated-only (anon → 42501), block-guarded
--     (is_blocked_either_way, symmetric).
--   * global_segment_effort_ranks: 1 + strictly-faster.

begin;

create extension if not exists pgtap with schema public;

select plan(13);

-- ── Fixture: admin curator, viewer A, other runner B, stranger S ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000c001', 'authenticated', 'authenticated',
   'curator@gc.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000c0a1', 'authenticated', 'authenticated',
   'viewer-a@gc.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000c0b2', 'authenticated', 'authenticated',
   'other-b@gc.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000c0c3', 'authenticated', 'authenticated',
   'stranger-s@gc.local', '', now(), now());

insert into user_profiles (id, display_name)
values
  ('00000000-0000-0000-0000-00000000c001', 'Curator'),
  ('00000000-0000-0000-0000-00000000c0a1', 'Viewer A'),
  ('00000000-0000-0000-0000-00000000c0b2', 'Other B'),
  ('00000000-0000-0000-0000-00000000c0c3', 'Stranger S');

-- Curator is an admin.
insert into app_admins (user_id) values ('00000000-0000-0000-0000-00000000c001');

-- Seed catalogue rows as service_role (bypasses RLS, mirrors seed.sql).
set local role service_role;
insert into global_segments (id, name, waypoints, distance_m, region, country_code, is_active)
values
  ('a1a1a1a1-0000-0000-0000-0000000000c1',
   'Famous Hill',
   '[{"lat":40.0,"lng":-73.0},{"lat":40.001,"lng":-73.0},{"lat":40.002,"lng":-73.0}]',
   400, 'Testville, US', 'US', true),
  ('a1a1a1a1-0000-0000-0000-0000000000c2',
   'Retired Segment',
   '[{"lat":40.0,"lng":-73.0},{"lat":40.001,"lng":-73.0}]',
   300, 'Testville, US', 'US', false);

-- 1. Anon sees the active catalogue segment.
set local role anon;
set local "request.jwt.claims" = '';
select results_eq(
  $$ select name from global_segments where id = 'a1a1a1a1-0000-0000-0000-0000000000c1' $$,
  $$ values ('Famous Hill'::text) $$,
  'anon can SELECT an active catalogue segment'
);

-- 2. Anon cannot see an inactive (pulled) catalogue segment.
select is_empty(
  $$ select id from global_segments where id = 'a1a1a1a1-0000-0000-0000-0000000000c2' $$,
  'anon cannot SELECT an inactive catalogue segment'
);

-- 3. A non-admin authenticated caller cannot INSERT a catalogue segment.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000c0a1"}';
select throws_ok(
  $$ insert into global_segments (name, waypoints, distance_m)
       values ('Sneaky', '[{"lat":1,"lng":1},{"lat":1.01,"lng":1}]', 500) $$,
  '42501',
  null,
  'non-admin cannot INSERT a catalogue segment'
);

-- 4. A non-admin cannot pull (UPDATE is_active) a catalogue segment.
update global_segments set is_active = false
  where id = 'a1a1a1a1-0000-0000-0000-0000000000c1';
select is(
  (select is_active from global_segments where id = 'a1a1a1a1-0000-0000-0000-0000000000c1'),
  true,
  'non-admin UPDATE on a catalogue segment is a no-op'
);

-- 5. The admin curator CAN insert a catalogue segment.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000c001"}';
insert into global_segments (id, name, waypoints, distance_m)
values ('a1a1a1a1-0000-0000-0000-0000000000c3',
        'Curated Climb', '[{"lat":2,"lng":2},{"lat":2.01,"lng":2}]', 600);
select results_eq(
  $$ select name from global_segments where id = 'a1a1a1a1-0000-0000-0000-0000000000c3' $$,
  $$ values ('Curated Climb'::text) $$,
  'admin curator can INSERT a catalogue segment'
);

-- ── Efforts ──
-- A records a PUBLIC run + effort; B records a PRIVATE run + effort.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000c0a1"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('b1b1b1b1-0000-0000-0000-0000000000a1',
        '00000000-0000-0000-0000-00000000c0a1', now(), 5000, 1200, 'app',
        '{"activity_type":"run"}'::jsonb, true);
insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at)
values ('a1a1a1a1-0000-0000-0000-0000000000c1',
        'b1b1b1b1-0000-0000-0000-0000000000a1',
        '00000000-0000-0000-0000-00000000c0a1', 200, now() - interval '2 hours');

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000c0b2"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('b1b1b1b1-0000-0000-0000-0000000000b2',
        '00000000-0000-0000-0000-00000000c0b2', now(), 5000, 1300, 'app',
        '{"activity_type":"run"}'::jsonb, false);
insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at)
values ('a1a1a1a1-0000-0000-0000-0000000000c1',
        'b1b1b1b1-0000-0000-0000-0000000000b2',
        '00000000-0000-0000-0000-00000000c0b2', 250, now() - interval '1 hour');

-- 6. Stranger cannot see B's effort on a PRIVATE run through the base table.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000c0c3"}';
select is_empty(
  $$ select id from global_segment_efforts
     where run_id = 'b1b1b1b1-0000-0000-0000-0000000000b2' $$,
  'stranger cannot SELECT an effort attached to a private run'
);

-- 7. Stranger CAN see A's effort on a PUBLIC run.
select results_eq(
  $$ select user_id::text from global_segment_efforts
     where run_id = 'b1b1b1b1-0000-0000-0000-0000000000a1' $$,
  $$ values ('00000000-0000-0000-0000-00000000c0a1'::text) $$,
  'stranger can SELECT an effort attached to a public run'
);

-- 8. Stranger cannot forge an effort on someone else''s run.
select throws_ok(
  $$ insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at)
       values ('a1a1a1a1-0000-0000-0000-0000000000c1',
               'b1b1b1b1-0000-0000-0000-0000000000a1',
               '00000000-0000-0000-0000-00000000c0c3', 999, now()) $$,
  '42501',
  null,
  'a user cannot INSERT an effort on another user''s run'
);

-- ── Leaderboard RPC ──
-- 9. Anon → 42501 (block guard needs a concrete caller).
set local role anon;
set local "request.jwt.claims" = '';
select throws_ok(
  $$ select * from global_segment_leaderboard('a1a1a1a1-0000-0000-0000-0000000000c1'::uuid) $$,
  '42501',
  null,
  'anon cannot call global_segment_leaderboard'
);

-- 10. Baseline: viewer A sees BOTH efforts (B''s private run is visible to A
--     only through the RPC? No — is_run_visible_to gates it). A sees own +
--     any public. B''s run is private, so A sees only A''s own effort.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000c0a1"}';
select is(
  (select count(*)::int from global_segment_leaderboard('a1a1a1a1-0000-0000-0000-0000000000c1'::uuid)),
  1,
  'leaderboard hides B''s effort (private run) from A; A sees own only'
);

-- Make B''s run public so the leaderboard has two comparable rows.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000c0b2"}';
update runs set is_public = true where id = 'b1b1b1b1-0000-0000-0000-0000000000b2';

-- 11. Now A sees both efforts.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000c0a1"}';
select is(
  (select count(*)::int from global_segment_leaderboard('a1a1a1a1-0000-0000-0000-0000000000c1'::uuid)),
  2,
  'leaderboard shows both efforts once both runs are public'
);

-- 12. A blocks B → B disappears from A''s board (symmetric guard).
insert into user_blocks (blocker_id, blocked_id)
values ('00000000-0000-0000-0000-00000000c0a1', '00000000-0000-0000-0000-00000000c0b2');
select is(
  (select user_id::text from global_segment_leaderboard('a1a1a1a1-0000-0000-0000-0000000000c1'::uuid)),
  '00000000-0000-0000-0000-00000000c0a1',
  'after A blocks B, only A''s own effort remains on the board'
);

-- 13. global_segment_effort_ranks: A''s effort (200s, fastest) ranks 1.
select is(
  (select rank from global_segment_effort_ranks('b1b1b1b1-0000-0000-0000-0000000000a1'::uuid)
     where effort_id = (select id from global_segment_efforts
                        where run_id = 'b1b1b1b1-0000-0000-0000-0000000000a1')),
  1,
  'global_segment_effort_ranks ranks the fastest effort #1'
);

select * from finish();
rollback;
