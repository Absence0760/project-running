-- Attendance, distinct from RSVP (instructor_business.md M6, migration
-- 20261231_006). A class host marks who actually showed up; the attendee's
-- own RSVP status stays orthogonal and untouched.
--
-- Write model under test:
--   - mark_attendance(event_id, user_id, attendance) — SECURITY DEFINER,
--     organiser-only (private.is_event_organiser on the event's club), writes
--     ONLY the attendance column. Invalid attendance value → check_violation.
--   - The self-only RSVP UPDATE policy ("users can update their own RSVP",
--     20260416_001) is left intact for `status`, but column UPDATE on
--     `attendance` is revoked from authenticated/anon, so an attendee cannot
--     self-mark attendance via a direct UPDATE — the RPC is the sole path.
--
-- Blast radius if the organiser check regresses: any authenticated user could
-- rewrite attendance on any event's roster. If the column revoke regresses:
-- an attendee could self-mark their own attendance, defeating "host-written".

begin;

select plan(7);

-- ── Fixture ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000b000001', 'authenticated', 'authenticated',
   'owner@att.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000b000002', 'authenticated', 'authenticated',
   'organiser@att.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000b000003', 'authenticated', 'authenticated',
   'member@att.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000b000004', 'authenticated', 'authenticated',
   'attendee@att.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public)
values
  ('cccccccc-cccc-cccc-cccc-cccccccc0b01',
   '00000000-0000-0000-0000-00000b000001',
   'Attendance Test Club', 'attendance-test', false);

insert into club_members (club_id, user_id, role, status)
values
  ('cccccccc-cccc-cccc-cccc-cccccccc0b01',
   '00000000-0000-0000-0000-00000b000002', 'event_organiser', 'active'),
  ('cccccccc-cccc-cccc-cccc-cccccccc0b01',
   '00000000-0000-0000-0000-00000b000003', 'member', 'active'),
  ('cccccccc-cccc-cccc-cccc-cccccccc0b01',
   '00000000-0000-0000-0000-00000b000004', 'member', 'active');

insert into events (id, club_id, title, category, starts_at, author_id)
values
  ('dddddddd-dddd-dddd-dddd-dddddddd0b01',
   'cccccccc-cccc-cccc-cccc-cccccccc0b01',
   'Tuesday Vinyasa', 'class',
   '2026-06-23 18:00:00+00',
   '00000000-0000-0000-0000-00000b000001');

-- The attendee RSVP'd 'going'.
insert into event_attendees (event_id, user_id, status, instance_start)
values
  ('dddddddd-dddd-dddd-dddd-dddddddd0b01',
   '00000000-0000-0000-0000-00000b000004',
   'going',
   '2026-06-23 18:00:00+00');

set local role authenticated;

-- 1. Organiser can mark an attendee attended via the RPC.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000b000002"}';
select lives_ok(
  $$ select mark_attendance(
       'dddddddd-dddd-dddd-dddd-dddddddd0b01',
       '00000000-0000-0000-0000-00000b000004',
       'attended') $$,
  'organiser can mark an attendee attended (positive control on RPC)'
);

-- 2. The attendance landed AND the RSVP status is untouched (orthogonal).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000b000001"}';
select results_eq(
  $$ select attendance, status from event_attendees
     where event_id = 'dddddddd-dddd-dddd-dddd-dddddddd0b01'
       and user_id = '00000000-0000-0000-0000-00000b000004' $$,
  $$ values ('attended'::text, 'going'::text) $$,
  'attendance set to attended; RSVP status stays going (orthogonal)'
);

-- 3. A plain member cannot mark attendance (organiser check fails).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000b000003"}';
select throws_ok(
  $$ select mark_attendance(
       'dddddddd-dddd-dddd-dddd-dddddddd0b01',
       '00000000-0000-0000-0000-00000b000004',
       'no_show') $$,
  '42501',
  null,
  'plain member cannot mark attendance (organiser-only RPC)'
);

-- 4. The failed member call did not change the stored attendance.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000b000001"}';
select results_eq(
  $$ select attendance from event_attendees
     where event_id = 'dddddddd-dddd-dddd-dddd-dddddddd0b01'
       and user_id = '00000000-0000-0000-0000-00000b000004' $$,
  $$ values ('attended'::text) $$,
  'member''s rejected mark left attendance unchanged'
);

-- 5. An invalid attendance value is rejected by the RPC.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000b000002"}';
select throws_ok(
  $$ select mark_attendance(
       'dddddddd-dddd-dddd-dddd-dddddddd0b01',
       '00000000-0000-0000-0000-00000b000004',
       'maybe') $$,
  '23514',
  null,
  'RPC rejects an attendance value outside attended/no_show'
);

-- 6. The self-only RSVP UPDATE path still works (attendee changes own status).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000b000004"}';
update event_attendees
  set status = 'maybe'
  where event_id = 'dddddddd-dddd-dddd-dddd-dddddddd0b01'
    and user_id = '00000000-0000-0000-0000-00000b000004';
select results_eq(
  $$ select status from event_attendees
     where event_id = 'dddddddd-dddd-dddd-dddd-dddddddd0b01'
       and user_id = '00000000-0000-0000-0000-00000b000004' $$,
  $$ values ('maybe'::text) $$,
  'self-only RSVP status UPDATE still works (orthogonal write path intact)'
);

-- 7. The attendee cannot self-mark attendance via a direct UPDATE — the
--    column-level revoke composes with the self-only policy to block it.
select throws_ok(
  $$ update event_attendees
       set attendance = 'no_show'
       where event_id = 'dddddddd-dddd-dddd-dddd-dddddddd0b01'
         and user_id = '00000000-0000-0000-0000-00000b000004' $$,
  '42501',
  null,
  'attendee cannot self-write attendance via direct UPDATE (column revoke)'
);

select * from finish();

rollback;
