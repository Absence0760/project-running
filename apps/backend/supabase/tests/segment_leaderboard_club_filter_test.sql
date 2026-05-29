-- Pins migration 20261022_001 — the p_club_id filter on
-- segment_leaderboard_tiered (social-group persona #50). A club member can
-- scope the board to their club; a non-member passing the club id gets an
-- empty board (no membership leak).

begin;
select plan(3);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('ffffffff-0000-0000-0000-0000000000c1', 'authenticated', 'authenticated', 'owner@clubseg.local', '', now(), now()),
  ('ffffffff-0000-0000-0000-0000000000c2', 'authenticated', 'authenticated', 'member@clubseg.local', '', now(), now()),
  ('ffffffff-0000-0000-0000-0000000000c3', 'authenticated', 'authenticated', 'outsider@clubseg.local', '', now(), now());

insert into user_profiles (id, display_name) values
  ('ffffffff-0000-0000-0000-0000000000c1', 'Owner'),
  ('ffffffff-0000-0000-0000-0000000000c2', 'Member'),
  ('ffffffff-0000-0000-0000-0000000000c3', 'Outsider');

-- Club (owner auto-enrolled by the enroll_club_owner trigger); add member c2.
insert into clubs (id, owner_id, name, slug, is_public)
values ('cccccccc-0000-0000-0000-0000000000d1',
        'ffffffff-0000-0000-0000-0000000000c1', 'Seg Club', 'seg-club', true);
insert into club_members (club_id, user_id, role, status)
values ('cccccccc-0000-0000-0000-0000000000d1',
        'ffffffff-0000-0000-0000-0000000000c2', 'member', 'active');

-- A public route + segment all three have run.
insert into routes (id, user_id, name, waypoints, distance_m, is_public)
values ('66666666-0000-0000-0000-000000000071',
        'ffffffff-0000-0000-0000-0000000000c1', 'Club Seg Loop', '[]'::jsonb, 5000, true);
insert into segments (id, route_id, name, start_distance_m, end_distance_m)
values ('55555555-0000-0000-0000-000000000051',
        '66666666-0000-0000-0000-000000000071', 'Sprint', 0, 1000);

-- One public run + one effort per user (public so is_run_visible_to passes).
insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, metadata) values
  ('11111111-0000-0000-0000-0000000000e1', 'ffffffff-0000-0000-0000-0000000000c1', '2026-04-01 09:00:00+00', 5000, 1500, 'app', true, '{"activity_type":"run"}'),
  ('22222222-0000-0000-0000-0000000000e2', 'ffffffff-0000-0000-0000-0000000000c2', '2026-04-02 09:00:00+00', 5000, 1500, 'app', true, '{"activity_type":"run"}'),
  ('33333333-0000-0000-0000-0000000000e3', 'ffffffff-0000-0000-0000-0000000000c3', '2026-04-03 09:00:00+00', 5000, 1500, 'app', true, '{"activity_type":"run"}');
insert into segment_efforts (segment_id, run_id, user_id, time_seconds, started_at) values
  ('55555555-0000-0000-0000-000000000051', '11111111-0000-0000-0000-0000000000e1', 'ffffffff-0000-0000-0000-0000000000c1', 300, '2026-04-01 09:00:00+00'),
  ('55555555-0000-0000-0000-000000000051', '22222222-0000-0000-0000-0000000000e2', 'ffffffff-0000-0000-0000-0000000000c2', 310, '2026-04-02 09:00:00+00'),
  ('55555555-0000-0000-0000-000000000051', '33333333-0000-0000-0000-0000000000e3', 'ffffffff-0000-0000-0000-0000000000c3', 320, '2026-04-03 09:00:00+00');

set local role authenticated;

-- Member (owner) with no club filter sees all three efforts.
set local "request.jwt.claims" = '{"sub":"ffffffff-0000-0000-0000-0000000000c1"}';
select is(
  (select count(*)::int from segment_leaderboard_tiered('55555555-0000-0000-0000-000000000051')),
  3, 'unfiltered board shows all three runners');

-- Same caller filtering to the club sees only the two members (not the outsider).
select is(
  (select count(*)::int from segment_leaderboard_tiered(
     '55555555-0000-0000-0000-000000000051', null, null, 50,
     'cccccccc-0000-0000-0000-0000000000d1')),
  2, 'club filter narrows to club members only');

-- A non-member passing the club id gets an empty board (no membership leak).
set local "request.jwt.claims" = '{"sub":"ffffffff-0000-0000-0000-0000000000c3"}';
select is(
  (select count(*)::int from segment_leaderboard_tiered(
     '55555555-0000-0000-0000-000000000051', null, null, 50,
     'cccccccc-0000-0000-0000-0000000000d1')),
  0, 'a non-member passing the club id gets nothing');

select * from finish();
rollback;
