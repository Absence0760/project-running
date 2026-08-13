-- Pins migration 20270524_001 on the two segment boards: the §206
-- shadow-hidden backstop reaches SECURITY DEFINER bodies that had inlined a
-- copy of a visibility predicate.
--
--   1. A stranger no longer reads the board of a segment on a moderation-
--      hidden route — the route branch now delegates to
--      private.is_route_visible_to instead of a bare `is_public = true`.
--   2. The closing direction is the ONLY one that moved: the hidden route's
--      owner keeps their board, a club member keeps a club route's board, and
--      an ordinary public route's board is untouched.
--   3. A shadow-hidden athlete keeps their row and their rank but loses their
--      name + avatar to every other viewer, and still sees their own.
--   4. Because the row is redacted rather than dropped, the run-detail chip
--      (segment_effort_ranks, SECURITY INVOKER, no profile gate) and the board
--      still agree — dropping it would silently reopen decisions § 594.
--   5. The catalogue board carries the same profile carve-out.

begin;

select plan(9);

-- ── Fixture: route owner, a shadow-hidden athlete, a stranger, a clubber ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000fb001', 'authenticated', 'authenticated',
   'owner@shb.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000fb002', 'authenticated', 'authenticated',
   'hidden@shb.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000fb003', 'authenticated', 'authenticated',
   'stranger@shb.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000fb004', 'authenticated', 'authenticated',
   'clubber@shb.local', '', now(), now());

-- The moderation flags are set by the auto-hide path, not by the user, so the
-- fixture writes them directly rather than through an authenticated session.
insert into user_profiles (id, display_name, avatar_url, shadow_hidden)
values
  ('00000000-0000-0000-0000-0000000fb001', 'Route Owner', 'https://x/o.png', false),
  ('00000000-0000-0000-0000-0000000fb002', 'Hidden Athlete', 'https://x/h.png', true),
  ('00000000-0000-0000-0000-0000000fb003', 'Stranger', 'https://x/s.png', false),
  ('00000000-0000-0000-0000-0000000fb004', 'Clubber', 'https://x/c.png', false);

select tests.confirm_consent();

insert into clubs (id, owner_id, name, slug)
values ('cccccccc-0000-0000-0000-0000000000b1',
        '00000000-0000-0000-0000-0000000fb001', 'Backstop CC', 'backstop-cc');
-- The owner's membership row is created by the club-insert trigger; only the
-- second member is added here.
insert into club_members (club_id, user_id, role, status)
values ('cccccccc-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000fb004', 'member', 'active');

-- Three routes owned by the same person: an ordinary public one, a
-- moderation-hidden public one, and a club-visibility one.
insert into routes (id, user_id, name, waypoints, distance_m, is_public, shadow_hidden, club_id)
values
  ('66666666-6666-6666-6666-66666666fb01', '00000000-0000-0000-0000-0000000fb001',
   'Open Loop', '[{"lat":47.37,"lng":8.54},{"lat":47.38,"lng":8.55}]', 10000, true, false, null),
  ('66666666-6666-6666-6666-66666666fb02', '00000000-0000-0000-0000-0000000fb001',
   'Hidden Loop', '[{"lat":47.37,"lng":8.54},{"lat":47.38,"lng":8.55}]', 10000, true, true, null),
  ('66666666-6666-6666-6666-66666666fb03', '00000000-0000-0000-0000-0000000fb001',
   'Club Loop', '[{"lat":47.37,"lng":8.54},{"lat":47.38,"lng":8.55}]', 10000, false, false,
   'cccccccc-0000-0000-0000-0000000000b1');

insert into segments (id, route_id, name, start_distance_m, end_distance_m, author_id)
values
  ('77777777-7777-7777-7777-77777777fb01', '66666666-6666-6666-6666-66666666fb01',
   'Open Climb', 500, 1500, '00000000-0000-0000-0000-0000000fb001'),
  ('77777777-7777-7777-7777-77777777fb02', '66666666-6666-6666-6666-66666666fb02',
   'Hidden Climb', 500, 1500, '00000000-0000-0000-0000-0000000fb001'),
  ('77777777-7777-7777-7777-77777777fb03', '66666666-6666-6666-6666-66666666fb03',
   'Club Climb', 500, 1500, '00000000-0000-0000-0000-0000000fb001');

insert into global_segments (id, name, waypoints, distance_m, is_active)
values ('a5a5a5a5-0000-0000-0000-0000000000b1', 'Catalogue Climb',
        '[{"lat":40.0,"lng":-73.0},{"lat":40.002,"lng":-73.0}]', 400, true);

set local role authenticated;

-- Owner: 100 s on the open climb, 100 s on the hidden climb.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000fb001"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('88888888-8888-8888-8888-88888888fb01', '00000000-0000-0000-0000-0000000fb001',
        now(), 10000, 1800, 'app', '{"activity_type":"run"}'::jsonb, true);
insert into segment_efforts (id, segment_id, run_id, user_id, time_seconds, started_at)
values
  ('99999999-9999-9999-9999-99999999fb01', '77777777-7777-7777-7777-77777777fb01',
   '88888888-8888-8888-8888-88888888fb01', '00000000-0000-0000-0000-0000000fb001', 100, now()),
  ('99999999-9999-9999-9999-99999999fb02', '77777777-7777-7777-7777-77777777fb02',
   '88888888-8888-8888-8888-88888888fb01', '00000000-0000-0000-0000-0000000fb001', 100, now());

-- The hidden athlete holds the fastest time on the open climb, and an effort
-- on the catalogue segment.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000fb002"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('88888888-8888-8888-8888-88888888fb02', '00000000-0000-0000-0000-0000000fb002',
        now(), 10000, 1700, 'app', '{"activity_type":"run"}'::jsonb, true);
insert into segment_efforts (id, segment_id, run_id, user_id, time_seconds, started_at)
values ('99999999-9999-9999-9999-99999999fb03', '77777777-7777-7777-7777-77777777fb01',
        '88888888-8888-8888-8888-88888888fb02', '00000000-0000-0000-0000-0000000fb002', 90, now());
insert into global_segment_efforts (id, global_segment_id, run_id, user_id, time_seconds, started_at)
values ('c5c5c5c5-0000-0000-0000-0000000000b1', 'a5a5a5a5-0000-0000-0000-0000000000b1',
        '88888888-8888-8888-8888-88888888fb02', '00000000-0000-0000-0000-0000000fb002', 90, now());

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000fb003"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('88888888-8888-8888-8888-88888888fb03', '00000000-0000-0000-0000-0000000fb003',
        now(), 10000, 1900, 'app', '{"activity_type":"run"}'::jsonb, true);
insert into segment_efforts (id, segment_id, run_id, user_id, time_seconds, started_at)
values ('99999999-9999-9999-9999-99999999fb04', '77777777-7777-7777-7777-77777777fb01',
        '88888888-8888-8888-8888-88888888fb03', '00000000-0000-0000-0000-0000000fb003', 110, now());
insert into global_segment_efforts (id, global_segment_id, run_id, user_id, time_seconds, started_at)
values ('c5c5c5c5-0000-0000-0000-0000000000b2', 'a5a5a5a5-0000-0000-0000-0000000000b1',
        '88888888-8888-8888-8888-88888888fb03', '00000000-0000-0000-0000-0000000fb003', 110, now());

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000fb004"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('88888888-8888-8888-8888-88888888fb04', '00000000-0000-0000-0000-0000000fb004',
        now(), 10000, 1800, 'app', '{"activity_type":"run"}'::jsonb, true);
insert into segment_efforts (id, segment_id, run_id, user_id, time_seconds, started_at)
values ('99999999-9999-9999-9999-99999999fb05', '77777777-7777-7777-7777-77777777fb03',
        '88888888-8888-8888-8888-88888888fb04', '00000000-0000-0000-0000-0000000fb004', 100, now());

-- ── Read as the stranger ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000fb003"}';

-- 1. The headline leak: a moderation-hidden route's board, reachable by
--    anyone holding the segment id, after 20270329_001 closed that route's
--    waypoints, photos, reviews, segments and markers.
select is(
  (select count(*)::int from segment_leaderboard_tiered(
     '77777777-7777-7777-7777-77777777fb02'::uuid)),
  0,
  'a stranger reads no board for a segment on a shadow-hidden route'
);

-- 2-3. Nothing narrowed for a legitimate viewer of an ordinary public route:
--      all three athletes are still on the board, in time order, and only the
--      hidden athlete''s identity is withheld.
select is(
  (select count(*)::int from segment_leaderboard_tiered(
     '77777777-7777-7777-7777-77777777fb01'::uuid)),
  3,
  'an ordinary public route''s board still carries every athlete'
);

select results_eq(
  $$ select user_id::text, time_seconds, display_name, avatar_url
       from segment_leaderboard_tiered('77777777-7777-7777-7777-77777777fb01'::uuid) $$,
  $$ values
       ('00000000-0000-0000-0000-0000000fb002', 90, null::text, null::text),
       ('00000000-0000-0000-0000-0000000fb001', 100, 'Route Owner', 'https://x/o.png'),
       ('00000000-0000-0000-0000-0000000fb003', 110, 'Stranger', 'https://x/s.png')
  $$,
  'a shadow-hidden athlete keeps their row and rank but loses name + avatar; '
  'everyone else is untouched'
);

-- 4. The row is redacted, not dropped, so the run-detail chip and the board
--    still agree — dropping it would reopen decisions § 594, because
--    segment_effort_ranks is SECURITY INVOKER over segment_efforts and has no
--    profile gate to drop the same athlete.
select is(
  (select rank from segment_effort_ranks('88888888-8888-8888-8888-88888888fb03'::uuid)),
  (select count(*)::int + 1 from segment_leaderboard_tiered(
     '77777777-7777-7777-7777-77777777fb01'::uuid) where time_seconds < 110),
  'chip and board still agree: the hidden athlete is counted by both'
);

-- 5. Catalogue board carries the same carve-out.
select results_eq(
  $$ select user_id::text, display_name from global_segment_leaderboard(
       'a5a5a5a5-0000-0000-0000-0000000000b1'::uuid) $$,
  $$ values
       ('00000000-0000-0000-0000-0000000fb002', null::text),
       ('00000000-0000-0000-0000-0000000fb003', 'Stranger')
  $$,
  'the catalogue board redacts a shadow-hidden athlete the same way'
);

-- ── 6-7. The owner still sees their own hidden route ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000fb001"}';

select is(
  (select count(*)::int from segment_leaderboard_tiered(
     '77777777-7777-7777-7777-77777777fb02'::uuid)),
  1,
  'the hidden route''s owner keeps their board (only the public branch moved)'
);

select is(
  (select count(*)::int from segment_leaderboard_tiered(
     '77777777-7777-7777-7777-77777777fb01'::uuid)),
  3,
  'the owner''s view of the ordinary board is unchanged'
);

-- ── 8. An active club member still sees a club route's board ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000fb004"}';

select is(
  (select count(*)::int from segment_leaderboard_tiered(
     '77777777-7777-7777-7777-77777777fb03'::uuid)),
  1,
  'an active club member keeps a club route''s board'
);

-- ── 9. The hidden athlete still sees their own name ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000fb002"}';

select is(
  (select display_name from segment_leaderboard_tiered(
     '77777777-7777-7777-7777-77777777fb01'::uuid)
     where user_id = '00000000-0000-0000-0000-0000000fb002'),
  'Hidden Athlete',
  'a shadow-hidden athlete still sees their own name (soft-hide, not deletion)'
);

select * from finish();
rollback;
