-- Capacity enforcement + waitlist triggers (migration 20261018_001,
-- event-organizer persona #42).
--
-- enforce_event_capacity demotes an over-capacity 'going' to 'waitlisted';
-- promote_event_waitlist promotes the earliest-joined waitlisted attendee
-- when a 'going' slot frees. Capacity is per (event_id, instance_start);
-- capacity NULL means unlimited. These are plain triggers (not RLS), so the
-- test drives them directly without role switching.
--
-- joined_at defaults to now(), which is constant within a single
-- transaction, so promotion order falls to the user_id tiebreak — the
-- fixture's user ids are ordered aa01 < aa02 < ... so aa03 promotes before
-- aa04 deterministically.

begin;

select plan(8);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01', 'authenticated', 'authenticated', 'c1@cap.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa02', 'authenticated', 'authenticated', 'c2@cap.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa03', 'authenticated', 'authenticated', 'c3@cap.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa04', 'authenticated', 'authenticated', 'c4@cap.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa05', 'authenticated', 'authenticated', 'c5@cap.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public)
values ('cccccccc-cccc-cccc-cccc-cccccccccc01',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01', 'Cap Club', 'cap-club', true);

insert into events (id, club_id, title, starts_at, author_id, capacity)
values
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01',
   'cccccccc-cccc-cccc-cccc-cccccccccc01', 'Capped Race',
   '2026-06-20 09:00:00+00', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01', 2),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee02',
   'cccccccc-cccc-cccc-cccc-cccccccccc01', 'Unlimited Run',
   '2026-06-20 09:00:00+00', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01', null);

-- ── Capped event (capacity = 2) ──
-- First two 'going' RSVPs stay going.
insert into event_attendees (event_id, user_id, status, instance_start) values
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01', 'going', '2026-06-20 09:00:00+00'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa02', 'going', '2026-06-20 09:00:00+00');
select is(
  (select count(*)::int from event_attendees
   where event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01' and status = 'going'),
  2, 'first two going RSVPs fill capacity and stay going');

-- Third 'going' is demoted to waitlisted.
insert into event_attendees (event_id, user_id, status, instance_start) values
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa03', 'going', '2026-06-20 09:00:00+00');
select is(
  (select status from event_attendees
   where event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01'
     and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa03'),
  'waitlisted', 'going RSVP over capacity is demoted to waitlisted');

-- Fourth 'going' also waitlisted.
insert into event_attendees (event_id, user_id, status, instance_start) values
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa04', 'going', '2026-06-20 09:00:00+00');
select is(
  (select count(*)::int from event_attendees
   where event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01' and status = 'waitlisted'),
  2, 'further over-capacity RSVPs join the waitlist');

-- Dropping a 'going' (delete) promotes the earliest waitlisted (aa03).
delete from event_attendees
  where event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01'
    and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01';
select is(
  (select status from event_attendees
   where event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01'
     and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa03'),
  'going', 'earliest waitlisted is auto-promoted when a going RSVP is deleted');
select is(
  (select count(*)::int from event_attendees
   where event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01' and status = 'going'),
  2, 'capacity stays full after auto-promotion');

-- Dropping a 'going' via status change (going -> declined) promotes aa04.
update event_attendees set status = 'declined'
  where event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01'
    and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa02';
select is(
  (select status from event_attendees
   where event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01'
     and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa04'),
  'going', 'next waitlisted promoted when a going RSVP changes to declined');

-- ── Unlimited event (capacity NULL) ──
insert into event_attendees (event_id, user_id, status, instance_start) values
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee02', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01', 'going', '2026-06-20 09:00:00+00'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee02', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa02', 'going', '2026-06-20 09:00:00+00'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee02', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa03', 'going', '2026-06-20 09:00:00+00');
select is(
  (select count(*)::int from event_attendees
   where event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee02' and status = 'going'),
  3, 'capacity NULL never waitlists');

-- 'maybe' never counts toward capacity and is never demoted (capped event
-- is full with aa03 + aa04 going).
insert into event_attendees (event_id, user_id, status, instance_start) values
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa05', 'maybe', '2026-06-20 09:00:00+00');
select is(
  (select status from event_attendees
   where event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01'
     and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa05'),
  'maybe', 'maybe RSVP is left untouched (never counts toward / hits capacity)');

select * from finish();

rollback;
