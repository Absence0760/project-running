-- Per-instance event cancellation: event_exceptions RLS + notify fan-out
-- (migration 20261019_001, parkrun / social-group persona #39).
--
-- Pins: only an event organiser can cancel an occurrence (and cannot forge
-- the cancelled_by audit actor); cancellation notifies every going / maybe /
-- waitlisted attendee of that instance but not declined attendees nor the
-- canceller; non-members can't read another club's exceptions; organisers can
-- reinstate (delete) an exception.

begin;

select plan(9);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaab01', 'authenticated', 'authenticated', 'owner@xcl.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaab02', 'authenticated', 'authenticated', 'org@xcl.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaab03', 'authenticated', 'authenticated', 'going@xcl.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaab04', 'authenticated', 'authenticated', 'maybe@xcl.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaab05', 'authenticated', 'authenticated', 'declined@xcl.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaab06', 'authenticated', 'authenticated', 'stranger@xcl.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public)
values ('cccccccc-cccc-cccc-cccc-ccccccccdd01',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaab01', 'Cancel Club', 'cancel-club', false);

insert into club_members (club_id, user_id, role, status) values
  ('cccccccc-cccc-cccc-cccc-ccccccccdd01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaab02', 'event_organiser', 'active'),
  ('cccccccc-cccc-cccc-cccc-ccccccccdd01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaab03', 'member', 'active'),
  ('cccccccc-cccc-cccc-cccc-ccccccccdd01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaab04', 'member', 'active'),
  ('cccccccc-cccc-cccc-cccc-ccccccccdd01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaab05', 'member', 'active');

insert into events (id, club_id, title, starts_at, created_by, recurrence_freq)
values ('eeeeeeee-eeee-eeee-eeee-eeeeeeeedd01',
        'cccccccc-cccc-cccc-cccc-ccccccccdd01', 'Weekly Parkrun',
        '2026-06-20 09:00:00+00', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaab01', 'weekly');

-- Attendees on the instance being cancelled.
insert into event_attendees (event_id, user_id, status, instance_start) values
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeedd01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaab03', 'going', '2026-06-20 09:00:00+00'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeedd01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaab04', 'maybe', '2026-06-20 09:00:00+00'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeedd01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaab05', 'declined', '2026-06-20 09:00:00+00');

set local role authenticated;

-- 1. Organiser cancels the 2026-06-20 occurrence.
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaab02"}';
select lives_ok(
  $$ insert into event_exceptions (event_id, instance_start, cancelled_by, reason)
     values ('eeeeeeee-eeee-eeee-eeee-eeeeeeeedd01', '2026-06-20 09:00:00+00',
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaab02', 'Course flooded') $$,
  'event organiser can cancel a single occurrence');

-- Notifications are inserted by the SECURITY DEFINER trigger; read them as
-- superuser so RLS on notifications doesn't gate the assertions.
reset role;
select is(
  (select count(*)::int from notifications
   where kind = 'event_cancel' and event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeedd01'
     and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaab03'),
  1, 'going attendee is notified of the cancellation');
select is(
  (select count(*)::int from notifications
   where kind = 'event_cancel' and event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeedd01'
     and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaab04'),
  1, 'maybe attendee is notified of the cancellation');
select is(
  (select count(*)::int from notifications
   where kind = 'event_cancel' and event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeedd01'
     and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaab05'),
  0, 'declined attendee is NOT notified');
select is(
  (select count(*)::int from notifications
   where kind = 'event_cancel' and event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeedd01'
     and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaab02'),
  0, 'the canceller is NOT notified');

-- 5. A plain member cannot cancel an occurrence.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaab03"}';
select throws_ok(
  $$ insert into event_exceptions (event_id, instance_start, cancelled_by)
     values ('eeeeeeee-eeee-eeee-eeee-eeeeeeeedd01', '2026-06-27 09:00:00+00',
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaab03') $$,
  '42501', null, 'a plain member cannot cancel an occurrence');

-- 6. The organiser cannot forge cancelled_by (audit integrity).
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaab02"}';
select throws_ok(
  $$ insert into event_exceptions (event_id, instance_start, cancelled_by)
     values ('eeeeeeee-eeee-eeee-eeee-eeeeeeeedd01', '2026-07-04 09:00:00+00',
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaab03') $$,
  '42501', null, 'cancelled_by cannot be forged (must equal auth.uid())');

-- 7. A stranger (non-member) cannot read a private club's exceptions.
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaab06"}';
select is_empty(
  $$ select 1 from event_exceptions
     where event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeedd01' $$,
  'a non-member cannot read exceptions of a private-club event');

-- 8. The organiser can reinstate (delete the exception).
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaab02"}';
delete from event_exceptions
  where event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeedd01'
    and instance_start = '2026-06-20 09:00:00+00';
reset role;
select is(
  (select count(*)::int from event_exceptions
   where event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeedd01'),
  0, 'organiser can reinstate an occurrence by deleting the exception');

select * from finish();

rollback;
