-- Pins the four status/policy CHECK constraints added by
-- 20261210_001_status_policy_check_constraints.sql (F16).
--
-- For each column: a representative legal value round-trips, and an
-- out-of-domain value is rejected with 23514 (check_violation) at write
-- time. Runs as the superuser (postgres) so RLS is out of the way — the
-- assertion under test is the CHECK, not a policy.

begin;

select plan(11);

-- Fixtures: two synthetic users + a club + an event. The seed user owns
-- the club so the auto-enroll trigger doesn't collide with our member row.
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000f1601', 'authenticated', 'authenticated',
   'f16a@test.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000f1602', 'authenticated', 'authenticated',
   'f16b@test.local', '', now(), now());

insert into clubs (id, owner_id, name, slug)
  values ('c1aaaaaa-0000-0000-0000-000000000001',
          'a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Test Club', 'test-club-f16');

insert into events (id, club_id, title, starts_at, created_by)
  values ('e1aaaaaa-0000-0000-0000-000000000001',
          'c1aaaaaa-0000-0000-0000-000000000001', 'Test Event',
          now() + interval '1 day',
          'a1b2c3d4-e5f6-7890-abcd-ef1234567890');

-- ─────────── event_attendees.status ───────────
-- instance_start is part of the PK (one-off events use starts_at).
select lives_ok(
  $$ insert into event_attendees (event_id, user_id, status, instance_start)
     values ('e1aaaaaa-0000-0000-0000-000000000001',
             '00000000-0000-0000-0000-0000000f1601', 'waitlisted', now() + interval '1 day') $$,
  'event_attendees accepts status = ''waitlisted'''
);
select throws_ok(
  $$ insert into event_attendees (event_id, user_id, status, instance_start)
     values ('e1aaaaaa-0000-0000-0000-000000000001',
             '00000000-0000-0000-0000-0000000f1602', 'attending', now() + interval '1 day') $$,
  '23514',
  null,
  'event_attendees rejects out-of-domain status'
);

-- ─────────── clubs.join_policy ───────────
select lives_ok(
  $$ update clubs set join_policy = 'invite'
     where id = 'c1aaaaaa-0000-0000-0000-000000000001' $$,
  'clubs accepts join_policy = ''invite'''
);
select throws_ok(
  $$ update clubs set join_policy = 'public'
     where id = 'c1aaaaaa-0000-0000-0000-000000000001' $$,
  '23514',
  null,
  'clubs rejects out-of-domain join_policy'
);

-- ─────────── club_members.status ───────────
select lives_ok(
  $$ insert into club_members (club_id, user_id, role, status)
     values ('c1aaaaaa-0000-0000-0000-000000000001',
             '00000000-0000-0000-0000-0000000f1601', 'member', 'rejected') $$,
  'club_members accepts status = ''rejected'''
);
select throws_ok(
  $$ insert into club_members (club_id, user_id, role, status)
     values ('c1aaaaaa-0000-0000-0000-000000000001',
             '00000000-0000-0000-0000-0000000f1602', 'member', 'banned') $$,
  '23514',
  null,
  'club_members rejects out-of-domain status'
);

-- ─────────── events.recurrence_freq ───────────
select lives_ok(
  $$ update events set recurrence_freq = 'biweekly'
     where id = 'e1aaaaaa-0000-0000-0000-000000000001' $$,
  'events accepts recurrence_freq = ''biweekly'''
);
select lives_ok(
  $$ update events set recurrence_freq = null
     where id = 'e1aaaaaa-0000-0000-0000-000000000001' $$,
  'events accepts recurrence_freq = null (one-off)'
);
select throws_ok(
  $$ update events set recurrence_freq = 'daily'
     where id = 'e1aaaaaa-0000-0000-0000-000000000001' $$,
  '23514',
  null,
  'events rejects out-of-domain recurrence_freq'
);

-- Constraint-presence smoke (catches a future drop of the named check).
select has_check(
  'public', 'clubs', 'clubs carries a CHECK constraint (join_policy)'
);
select has_check(
  'public', 'club_members', 'club_members carries a CHECK constraint (status)'
);

select * from finish();
rollback;
