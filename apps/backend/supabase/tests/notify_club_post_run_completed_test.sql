-- Notification fan-out for club posts + completed runs (migration
-- 20261101_001, persona #38).
--
-- Pins: a new club post notifies every ACTIVE member except the author
-- (pending join-requests are skipped); a fresh public run notifies the
-- runner's followers but not non-followers; a private run notifies nobody;
-- an old (>24 h) public run is skipped so a bulk history import can't
-- explode follower inboxes.

begin;

select plan(9);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3801', 'authenticated', 'authenticated', 'author@n38.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3802', 'authenticated', 'authenticated', 'active@n38.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3803', 'authenticated', 'authenticated', 'pending@n38.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3804', 'authenticated', 'authenticated', 'runner@n38.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3805', 'authenticated', 'authenticated', 'follower@n38.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3806', 'authenticated', 'authenticated', 'stranger@n38.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public)
values ('cccccccc-cccc-cccc-cccc-cccccccc3801',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3801', 'Notify Club', 'notify-club', true);

-- The owner is auto-enrolled as an active member by the club-create
-- trigger, so we only add the extra active + pending members here.
insert into club_members (club_id, user_id, role, status) values
  ('cccccccc-cccc-cccc-cccc-cccccccc3801', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3802', 'member', 'active'),
  ('cccccccc-cccc-cccc-cccc-cccccccc3801', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3803', 'member', 'pending');

-- ─────────── club_post fan-out ───────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3801"}';
select lives_ok(
  $$ insert into club_posts (club_id, author_id, body)
     values ('cccccccc-cccc-cccc-cccc-cccccccc3801',
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3801', 'Course change this Saturday') $$,
  'owner can post to the club feed');

reset role;
select is(
  (select count(*)::int from notifications
   where kind = 'club_post' and club_id = 'cccccccc-cccc-cccc-cccc-cccccccc3801'
     and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3802'),
  1, 'active member is notified of a new club post');
select is(
  (select count(*)::int from notifications
   where kind = 'club_post' and club_id = 'cccccccc-cccc-cccc-cccc-cccccccc3801'
     and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3803'),
  0, 'a pending (not-yet-approved) member is NOT notified');
select is(
  (select count(*)::int from notifications
   where kind = 'club_post' and club_id = 'cccccccc-cccc-cccc-cccc-cccccccc3801'
     and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3801'),
  0, 'the post author is NOT notified of their own post');

-- ─────────── run_completed fan-out ───────────

-- follower follows runner; stranger does not.
insert into user_follows (follower_id, followee_id) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3805', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3804');

-- 5. A fresh public run by the runner notifies the follower.
insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_public, metadata)
values ('11111111-1111-1111-1111-1111111138a1',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3804', now() - interval '30 minutes',
        1800, 5000, 'app', true, '{"activity_type":"run"}');
select is(
  (select count(*)::int from notifications
   where kind = 'run_completed' and run_id = '11111111-1111-1111-1111-1111111138a1'
     and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3805'),
  1, 'a follower is notified of a fresh public run');
select is(
  (select count(*)::int from notifications
   where kind = 'run_completed' and run_id = '11111111-1111-1111-1111-1111111138a1'
     and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3806'),
  0, 'a non-follower is NOT notified');

-- 7. A private run notifies nobody.
insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_public, metadata)
values ('11111111-1111-1111-1111-1111111138a2',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3804', now() - interval '10 minutes',
        1200, 3000, 'app', false, '{"activity_type":"run"}');
select is(
  (select count(*)::int from notifications
   where kind = 'run_completed' and run_id = '11111111-1111-1111-1111-1111111138a2'),
  0, 'a private run notifies nobody');

-- 8. An old (>24 h) public run is skipped — the bulk-import guard.
insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_public, metadata)
values ('11111111-1111-1111-1111-1111111138a3',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3804', now() - interval '5 days',
        1800, 5000, 'strava', true, '{"activity_type":"run"}');
select is(
  (select count(*)::int from notifications
   where kind = 'run_completed' and run_id = '11111111-1111-1111-1111-1111111138a3'),
  0, 'a public run older than 24h (bulk import / late sync) is skipped');

-- 9. The runner is never notified of their own run.
select is(
  (select count(*)::int from notifications
   where kind = 'run_completed' and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa3804'),
  0, 'the runner is NOT notified of their own run');

select * from finish();

rollback;
