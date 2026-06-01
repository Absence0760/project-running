-- Event-RSVP notification fan-out to the event-ops team (migration
-- 20261121_001, persona round-5 social-group).
--
-- Pins: a "going" RSVP notifies the event creator AND any co-organiser
-- holding the event_organiser / race_director role; a plain member who
-- is not the creator is NOT notified; the RSVPer never notifies
-- themselves.

begin;

select plan(5);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaae001', 'authenticated', 'authenticated', 'owner@ev.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaae002', 'authenticated', 'authenticated', 'organiser@ev.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaae003', 'authenticated', 'authenticated', 'member@ev.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaae004', 'authenticated', 'authenticated', 'rsvper@ev.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public)
values ('cccccccc-cccc-cccc-cccc-cccccccce001',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaae001', 'Event Club', 'event-club', true);

-- Owner is auto-enrolled active by the club-create trigger. Add a
-- co-organiser, a plain member, and the RSVPer.
insert into club_members (club_id, user_id, role, status) values
  ('cccccccc-cccc-cccc-cccc-cccccccce001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaae002', 'event_organiser', 'active'),
  ('cccccccc-cccc-cccc-cccc-cccccccce001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaae003', 'member', 'active'),
  ('cccccccc-cccc-cccc-cccc-cccccccce001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaae004', 'member', 'active');

-- Event created by the owner.
insert into events (id, club_id, title, starts_at, created_by)
values ('eeeeeeee-eeee-eeee-eeee-eeeeeeeee001',
        'cccccccc-cccc-cccc-cccc-cccccccce001', 'Saturday Long Run',
        now() + interval '2 days', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaae001');

-- The RSVPer says "going".
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaae004"}';
select lives_ok(
  $$ insert into event_attendees (event_id, user_id, status, instance_start)
     values ('eeeeeeee-eeee-eeee-eeee-eeeeeeeee001',
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaae004', 'going',
             now() + interval '2 days') $$,
  'a member can RSVP going to the event');

reset role;

select is(
  (select count(*)::int from notifications
   where kind = 'event_rsvp' and event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeee001'
     and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaae001'),
  1, 'the event creator is notified of the RSVP');

select is(
  (select count(*)::int from notifications
   where kind = 'event_rsvp' and event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeee001'
     and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaae002'),
  1, 'a co-organiser (event_organiser role) is also notified');

select is(
  (select count(*)::int from notifications
   where kind = 'event_rsvp' and event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeee001'
     and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaae003'),
  0, 'a plain member is NOT notified');

select is(
  (select count(*)::int from notifications
   where kind = 'event_rsvp' and event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeee001'
     and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaae004'),
  0, 'the RSVPer is not notified of their own RSVP');

select * from finish();
rollback;
