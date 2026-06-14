-- Attendance — full behavioural matrix (instructor_business.md M6; migrations
-- 20270102_001 + 20270130_001). Complements event_attendance_test.sql (which
-- pins the organiser-gate + sole-write-path) with the interaction + lifecycle
-- + multi-instance + roster cases:
--
--   A. Full event x attendance — attendance is ORTHOGONAL to capacity/waitlist:
--      a waitlisted attendee can be marked attended (status stays waitlisted),
--      and marking a 'going' attendee no_show does NOT free their slot (no
--      auto-promotion of the waitlist).
--   B. Full lifecycle on one attendee — attended -> idempotent re-mark -> toggle
--      no_show -> clear back to NULL; and a 'declined' attendee can still be
--      marked attended (attendance independent of RSVP status).
--   C. Recurring class — three occurrences of one attendee marked independently
--      (attended / no_show / left NULL); no cross-instance bleed.
--   D. Roster-wide — three attendees on one occurrence marked to three different
--      states in one pass.

begin;

select plan(19);

-- ── Users ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000fa000001', 'authenticated', 'authenticated',
   'owner@fa.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000fa000003', 'authenticated', 'authenticated',
   'u1@fa.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000fa000004', 'authenticated', 'authenticated',
   'u2@fa.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000fa000005', 'authenticated', 'authenticated',
   'u3@fa.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000fa000006', 'authenticated', 'authenticated',
   'u4@fa.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public)
values
  ('cccccccc-cccc-cccc-cccc-ccccfa000001',
   '00000000-0000-0000-0000-0000fa000001',
   'Full Attendance Club', 'full-attendance', false);

insert into club_members (club_id, user_id, role, status)
values
  ('cccccccc-cccc-cccc-cccc-ccccfa000001', '00000000-0000-0000-0000-0000fa000003', 'member', 'active'),
  ('cccccccc-cccc-cccc-cccc-ccccfa000001', '00000000-0000-0000-0000-0000fa000004', 'member', 'active'),
  ('cccccccc-cccc-cccc-cccc-ccccfa000001', '00000000-0000-0000-0000-0000fa000005', 'member', 'active'),
  ('cccccccc-cccc-cccc-cccc-ccccfa000001', '00000000-0000-0000-0000-0000fa000006', 'member', 'active');

-- A capacity-1 class (Group A) and an uncapped class (Groups B/C/D).
insert into events (id, club_id, title, category, starts_at, author_id, capacity)
values
  ('dddddddd-dddd-dddd-dddd-ddddfa000001',
   'cccccccc-cccc-cccc-cccc-ccccfa000001',
   'Capped Vinyasa', 'class', '2026-07-07 18:00:00+00',
   '00000000-0000-0000-0000-0000fa000001', 1),
  ('dddddddd-dddd-dddd-dddd-ddddfa000002',
   'cccccccc-cccc-cccc-cccc-ccccfa000001',
   'Open Vinyasa', 'class', '2026-07-07 18:00:00+00',
   '00000000-0000-0000-0000-0000fa000001', null);

-- Group A rows: u1 fills the single slot, u2's 'going' is demoted to
-- 'waitlisted' by enforce_event_capacity (order matters — u1 first).
insert into event_attendees (event_id, user_id, status, instance_start) values
  ('dddddddd-dddd-dddd-dddd-ddddfa000001', '00000000-0000-0000-0000-0000fa000003', 'going', '2026-07-07 18:00:00+00');
insert into event_attendees (event_id, user_id, status, instance_start) values
  ('dddddddd-dddd-dddd-dddd-ddddfa000001', '00000000-0000-0000-0000-0000fa000004', 'going', '2026-07-07 18:00:00+00');

-- Group B rows: u1 (lifecycle) + u4 (declined) on the open class.
insert into event_attendees (event_id, user_id, status, instance_start) values
  ('dddddddd-dddd-dddd-dddd-ddddfa000002', '00000000-0000-0000-0000-0000fa000003', 'going', '2026-07-07 18:00:00+00'),
  ('dddddddd-dddd-dddd-dddd-ddddfa000002', '00000000-0000-0000-0000-0000fa000006', 'declined', '2026-07-07 18:00:00+00');

-- Group C rows: u2 going on three occurrences of the open class.
insert into event_attendees (event_id, user_id, status, instance_start) values
  ('dddddddd-dddd-dddd-dddd-ddddfa000002', '00000000-0000-0000-0000-0000fa000004', 'going', '2026-07-14 18:00:00+00'),
  ('dddddddd-dddd-dddd-dddd-ddddfa000002', '00000000-0000-0000-0000-0000fa000004', 'going', '2026-07-21 18:00:00+00'),
  ('dddddddd-dddd-dddd-dddd-ddddfa000002', '00000000-0000-0000-0000-0000fa000004', 'going', '2026-07-28 18:00:00+00');

-- Group D rows: u1/u2/u3 going on one occurrence of the open class.
insert into event_attendees (event_id, user_id, status, instance_start) values
  ('dddddddd-dddd-dddd-dddd-ddddfa000002', '00000000-0000-0000-0000-0000fa000003', 'going', '2026-08-04 18:00:00+00'),
  ('dddddddd-dddd-dddd-dddd-ddddfa000002', '00000000-0000-0000-0000-0000fa000004', 'going', '2026-08-04 18:00:00+00'),
  ('dddddddd-dddd-dddd-dddd-ddddfa000002', '00000000-0000-0000-0000-0000fa000005', 'going', '2026-08-04 18:00:00+00');

set local role authenticated;
-- The club owner is an organiser; they mark + read throughout.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000fa000001"}';

-- ───────────────── Group A — full event x attendance ─────────────────

-- A1. Precondition: u2's 'going' was demoted to 'waitlisted' (event is full).
select is(
  (select status from event_attendees
   where event_id = 'dddddddd-dddd-dddd-dddd-ddddfa000001'
     and user_id = '00000000-0000-0000-0000-0000fa000004'),
  'waitlisted',
  'capacity-1 event waitlisted the second going RSVP (precondition)'
);

-- A2. A waitlisted attendee can still be marked attended.
select lives_ok(
  $$ select mark_attendance(
       'dddddddd-dddd-dddd-dddd-ddddfa000001',
       '00000000-0000-0000-0000-0000fa000004',
       '2026-07-07 18:00:00+00', 'attended') $$,
  'organiser can mark a waitlisted attendee attended'
);

-- A3. Marking a going attendee no_show keeps their slot (no auto-promote).
select lives_ok(
  $$ select mark_attendance(
       'dddddddd-dddd-dddd-dddd-ddddfa000001',
       '00000000-0000-0000-0000-0000fa000003',
       '2026-07-07 18:00:00+00', 'no_show') $$,
  'organiser can mark the going attendee no_show'
);

-- A4. Attendance is orthogonal to capacity: u1 stays going (no_show didn't free
--     the slot), u2 stays waitlisted (not promoted) — only attendance changed.
select results_eq(
  $$ select user_id, status, attendance from event_attendees
     where event_id = 'dddddddd-dddd-dddd-dddd-ddddfa000001'
     order by user_id $$,
  $$ values
       ('00000000-0000-0000-0000-0000fa000003'::uuid, 'going'::text, 'no_show'::text),
       ('00000000-0000-0000-0000-0000fa000004'::uuid, 'waitlisted'::text, 'attended'::text) $$,
  'attendance is orthogonal to capacity: no slot freed, no waitlist promotion'
);

-- ───────────────── Group B — full lifecycle on one attendee ─────────────────

-- B1/B2. Mark attended.
select lives_ok(
  $$ select mark_attendance(
       'dddddddd-dddd-dddd-dddd-ddddfa000002',
       '00000000-0000-0000-0000-0000fa000003',
       '2026-07-07 18:00:00+00', 'attended') $$,
  'lifecycle: mark attended'
);
select is(
  (select attendance from event_attendees
   where event_id = 'dddddddd-dddd-dddd-dddd-ddddfa000002'
     and user_id = '00000000-0000-0000-0000-0000fa000003'
     and instance_start = '2026-07-07 18:00:00+00'),
  'attended', 'lifecycle: attendance is attended');

-- B3. Re-marking attended is idempotent (no error, same value).
select lives_ok(
  $$ select mark_attendance(
       'dddddddd-dddd-dddd-dddd-ddddfa000002',
       '00000000-0000-0000-0000-0000fa000003',
       '2026-07-07 18:00:00+00', 'attended') $$,
  'lifecycle: re-marking attended is idempotent'
);

-- B4/B5. Toggle to no_show.
select lives_ok(
  $$ select mark_attendance(
       'dddddddd-dddd-dddd-dddd-ddddfa000002',
       '00000000-0000-0000-0000-0000fa000003',
       '2026-07-07 18:00:00+00', 'no_show') $$,
  'lifecycle: toggle to no_show'
);
select is(
  (select attendance from event_attendees
   where event_id = 'dddddddd-dddd-dddd-dddd-ddddfa000002'
     and user_id = '00000000-0000-0000-0000-0000fa000003'
     and instance_start = '2026-07-07 18:00:00+00'),
  'no_show', 'lifecycle: attendance is now no_show');

-- B6/B7. Clear back to NULL (passing null un-marks).
select lives_ok(
  $$ select mark_attendance(
       'dddddddd-dddd-dddd-dddd-ddddfa000002',
       '00000000-0000-0000-0000-0000fa000003',
       '2026-07-07 18:00:00+00', null) $$,
  'lifecycle: clear the mark with a null value'
);
select is(
  (select attendance from event_attendees
   where event_id = 'dddddddd-dddd-dddd-dddd-ddddfa000002'
     and user_id = '00000000-0000-0000-0000-0000fa000003'
     and instance_start = '2026-07-07 18:00:00+00'),
  null, 'lifecycle: attendance cleared back to NULL');

-- B8/B9. A 'declined' attendee can still be marked attended (orthogonal to RSVP).
select lives_ok(
  $$ select mark_attendance(
       'dddddddd-dddd-dddd-dddd-ddddfa000002',
       '00000000-0000-0000-0000-0000fa000006',
       '2026-07-07 18:00:00+00', 'attended') $$,
  'a declined attendee can still be marked attended'
);
select results_eq(
  $$ select status, attendance from event_attendees
     where event_id = 'dddddddd-dddd-dddd-dddd-ddddfa000002'
       and user_id = '00000000-0000-0000-0000-0000fa000006'
       and instance_start = '2026-07-07 18:00:00+00' $$,
  $$ values ('declined'::text, 'attended'::text) $$,
  'attendance set; RSVP status stays declined (orthogonal)'
);

-- ───────────────── Group C — recurring class, all instances ─────────────────

select lives_ok(
  $$ select mark_attendance(
       'dddddddd-dddd-dddd-dddd-ddddfa000002',
       '00000000-0000-0000-0000-0000fa000004',
       '2026-07-14 18:00:00+00', 'attended') $$,
  'recurring: mark occurrence 1 attended'
);
select lives_ok(
  $$ select mark_attendance(
       'dddddddd-dddd-dddd-dddd-ddddfa000002',
       '00000000-0000-0000-0000-0000fa000004',
       '2026-07-21 18:00:00+00', 'no_show') $$,
  'recurring: mark occurrence 2 no_show'
);
-- Occurrence 3 left unmarked; each occurrence is independent.
select results_eq(
  $$ select instance_start, attendance from event_attendees
     where event_id = 'dddddddd-dddd-dddd-dddd-ddddfa000002'
       and user_id = '00000000-0000-0000-0000-0000fa000004'
       and instance_start in ('2026-07-14 18:00:00+00','2026-07-21 18:00:00+00','2026-07-28 18:00:00+00')
     order by instance_start $$,
  $$ values
       ('2026-07-14 18:00:00+00'::timestamptz, 'attended'::text),
       ('2026-07-21 18:00:00+00'::timestamptz, 'no_show'::text),
       ('2026-07-28 18:00:00+00'::timestamptz, null::text) $$,
  'recurring: three occurrences marked independently, no cross-instance bleed'
);

-- ───────────────── Group D — roster-wide, one occurrence ─────────────────

select lives_ok(
  $$ select mark_attendance(
       'dddddddd-dddd-dddd-dddd-ddddfa000002',
       '00000000-0000-0000-0000-0000fa000003',
       '2026-08-04 18:00:00+00', 'attended') $$,
  'roster: mark attendee 1 attended'
);
select lives_ok(
  $$ select mark_attendance(
       'dddddddd-dddd-dddd-dddd-ddddfa000002',
       '00000000-0000-0000-0000-0000fa000004',
       '2026-08-04 18:00:00+00', 'no_show') $$,
  'roster: mark attendee 2 no_show'
);
-- Attendee 3 left unmarked; the roster carries three distinct states.
select results_eq(
  $$ select user_id, status, attendance from event_attendees
     where event_id = 'dddddddd-dddd-dddd-dddd-ddddfa000002'
       and instance_start = '2026-08-04 18:00:00+00'
     order by user_id $$,
  $$ values
       ('00000000-0000-0000-0000-0000fa000003'::uuid, 'going'::text, 'attended'::text),
       ('00000000-0000-0000-0000-0000fa000004'::uuid, 'going'::text, 'no_show'::text),
       ('00000000-0000-0000-0000-0000fa000005'::uuid, 'going'::text, null::text) $$,
  'roster: three attendees on one occurrence hold three independent states'
);

select * from finish();

rollback;
