-- RLS suite for `public.event_attendees` (RSVPs).
--
-- Policy stack (per migrations 20260416_001, 20260417_001 (per-
-- instance PK), 20260428_001 (organiser-add path), 20260617_001
-- (drop legacy duplicate "users can RSVP"), 20260629_001
-- (self-RSVP visibility gate)):
--
--   - SELECT "attendees readable with their event" — caller must
--     see the parent event (which itself gates on parent-club
--     visibility).
--   - INSERT "users RSVP to visible events" — caller=user_id AND
--     event must be visible to caller (the 20260629_001 visibility
--     gate; pre-fix, an authenticated user could plant RSVPs against
--     enumerated private-club event_ids, polluting attendee counts).
--   - INSERT "organisers add attendees to their events" —
--     `is_event_organiser` on the event's club. Used to register
--     walk-up participants who don't have the app.
--   - UPDATE "users can update their own RSVP" — own row.
--   - DELETE "users can delete their own RSVP" — own row.
--
-- The PK is `(event_id, user_id, instance_start)` (20260417_001
-- per-instance shape): the same user can RSVP separately to each
-- instance of a recurring series.
--
-- Blast radius if INSERT visibility gate regresses: attendee counts
-- on every private-club event become forgeable, and the planted
-- RSVPer's name appears in the attendee list that organisers see.
-- If self-RSVP `auth.uid() = user_id` regresses: cross-user RSVPs
-- on another's behalf (signing up a stranger to an event).

begin;

select plan(10);

-- ── Fixture ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000a000001', 'authenticated', 'authenticated',
   'owner@rsvp.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000a000002', 'authenticated', 'authenticated',
   'organiser@rsvp.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000a000003', 'authenticated', 'authenticated',
   'member@rsvp.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000a000004', 'authenticated', 'authenticated',
   'walkup@rsvp.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000a000005', 'authenticated', 'authenticated',
   'stranger@rsvp.local', '', now(), now());

-- Pre-role-switch fixture (bypasses RLS).
insert into clubs (id, owner_id, name, slug, is_public)
values
  ('cccccccc-cccc-cccc-cccc-cccccccc0001',
   '00000000-0000-0000-0000-00000a000001',
   'RSVP Test Club', 'rsvp-test', false);

insert into club_members (club_id, user_id, role, status)
values
  ('cccccccc-cccc-cccc-cccc-cccccccc0001',
   '00000000-0000-0000-0000-00000a000002', 'event_organiser', 'active'),
  ('cccccccc-cccc-cccc-cccc-cccccccc0001',
   '00000000-0000-0000-0000-00000a000003', 'member', 'active'),
  ('cccccccc-cccc-cccc-cccc-cccccccc0001',
   '00000000-0000-0000-0000-00000a000004', 'member', 'active');

insert into events (id, club_id, title, starts_at, author_id)
values
  ('dddddddd-dddd-dddd-dddd-dddddddd0001',
   'cccccccc-cccc-cccc-cccc-cccccccc0001',
   'Saturday Long Run',
   '2026-06-20 09:00:00+00',
   '00000000-0000-0000-0000-00000a000001');

-- Plant a member's pre-existing RSVP so SELECT / UPDATE / DELETE
-- tests have something to target.
insert into event_attendees (event_id, user_id, status, instance_start)
values
  ('dddddddd-dddd-dddd-dddd-dddddddd0001',
   '00000000-0000-0000-0000-00000a000003',
   'going',
   '2026-06-20 09:00:00+00');

set local role authenticated;

-- 1. Active member can SELECT the RSVP roster of an event in their
--    private club.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000a000003"}';
select results_eq(
  $$ select status from event_attendees
     where event_id = 'dddddddd-dddd-dddd-dddd-dddddddd0001'
       and user_id = '00000000-0000-0000-0000-00000a000003' $$,
  $$ values ('going'::text) $$,
  'active member can SELECT RSVPs of their club event'
);

-- 2. Stranger cannot SELECT RSVPs of an event in a private club
--    they don't belong to.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000a000005"}';
select is_empty(
  $$ select user_id from event_attendees
     where event_id = 'dddddddd-dddd-dddd-dddd-dddddddd0001' $$,
  'stranger cannot SELECT RSVPs of a private-club event'
);

-- 3. Active member can self-RSVP to their club's event (positive
--    control on the 20260629_001-gated INSERT).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000a000004"}';
insert into event_attendees (event_id, user_id, status, instance_start)
values
  ('dddddddd-dddd-dddd-dddd-dddddddd0001',
   '00000000-0000-0000-0000-00000a000004',
   'going',
   '2026-06-20 09:00:00+00');
select results_eq(
  $$ select count(*)::int from event_attendees
     where event_id = 'dddddddd-dddd-dddd-dddd-dddddddd0001'
       and user_id = '00000000-0000-0000-0000-00000a000004' $$,
  $$ values (1) $$,
  'active member can self-RSVP to their club event (positive)'
);

-- 4. Stranger self-RSVP to a private-club event is rejected. This
--    is the 20260629_001 closure — pre-fix, the auth.uid()=user_id
--    branch alone let any authenticated user plant RSVPs against
--    enumerated private-club event_ids.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000a000005"}';
select throws_ok(
  $$ insert into event_attendees (event_id, user_id, status, instance_start)
       values ('dddddddd-dddd-dddd-dddd-dddddddd0001',
               '00000000-0000-0000-0000-00000a000005',
               'going',
               '2026-06-20 09:00:00+00') $$,
  '42501',
  null,
  'stranger cannot self-RSVP to an invisible private-club event (visibility gate)'
);

-- 5. Forged user_id self-RSVP is rejected (cannot sign another
--    user up for an event).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000a000003"}';
select throws_ok(
  $$ insert into event_attendees (event_id, user_id, status, instance_start)
       values ('dddddddd-dddd-dddd-dddd-dddddddd0001',
               '00000000-0000-0000-0000-00000a000005',
               'going',
               '2026-06-20 09:00:00+00') $$,
  '42501',
  null,
  'cannot sign another user up for an event via forged user_id'
);

-- 6. Event organiser can add another user (walk-up registration).
--    The "organisers add attendees to their events" branch fires
--    on `is_event_organiser(e.club_id)`.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000a000002"}';
insert into event_attendees (event_id, user_id, status, instance_start)
values
  ('dddddddd-dddd-dddd-dddd-dddddddd0001',
   '00000000-0000-0000-0000-00000a000005',
   'going',
   '2026-06-20 09:00:00+00');
-- Verify the planted row exists by reading as the organiser (who
-- can see the event roster via membership).
select results_eq(
  $$ select status from event_attendees
     where event_id = 'dddddddd-dddd-dddd-dddd-dddddddd0001'
       and user_id = '00000000-0000-0000-0000-00000a000005' $$,
  $$ values ('going'::text) $$,
  'organiser can register a walk-up attendee (positive control on organiser-add branch)'
);

-- 7. Plain member cannot register another user (organiser-add
--    branch fails; self-RSVP branch fails because user_id != caller).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000a000003"}';
select throws_ok(
  $$ insert into event_attendees (event_id, user_id, status, instance_start)
       values ('dddddddd-dddd-dddd-dddd-dddddddd0001',
               '00000000-0000-0000-0000-00000a000001',
               'going',
               '2026-06-20 09:00:00+00') $$,
  '42501',
  null,
  'plain member cannot register another user (no organiser role + forged user_id)'
);

-- 8. User can UPDATE their own RSVP status.
update event_attendees
  set status = 'maybe'
  where event_id = 'dddddddd-dddd-dddd-dddd-dddddddd0001'
    and user_id = '00000000-0000-0000-0000-00000a000003';
select results_eq(
  $$ select status from event_attendees
     where event_id = 'dddddddd-dddd-dddd-dddd-dddddddd0001'
       and user_id = '00000000-0000-0000-0000-00000a000003' $$,
  $$ values ('maybe'::text) $$,
  'user can UPDATE their own RSVP status'
);

-- 9. Cross-user UPDATE is a silent no-op. Notice there is NO
--    organiser-UPDATE policy — even the walk-up-adder cannot later
--    flip the walk-up user's RSVP back to declined. That's by
--    design (the walked-up user is the canonical owner of their
--    own RSVP).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000a000002"}';
update event_attendees
  set status = 'declined'
  where event_id = 'dddddddd-dddd-dddd-dddd-dddddddd0001'
    and user_id = '00000000-0000-0000-0000-00000a000003';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000a000003"}';
select results_eq(
  $$ select status from event_attendees
     where event_id = 'dddddddd-dddd-dddd-dddd-dddddddd0001'
       and user_id = '00000000-0000-0000-0000-00000a000003' $$,
  $$ values ('maybe'::text) $$,
  'organiser cannot UPDATE another user''s RSVP (own-row policy is the only write path)'
);

-- 10. User can DELETE their own RSVP (cancel).
delete from event_attendees
  where event_id = 'dddddddd-dddd-dddd-dddd-dddddddd0001'
    and user_id = '00000000-0000-0000-0000-00000a000003';
select is_empty(
  $$ select status from event_attendees
     where event_id = 'dddddddd-dddd-dddd-dddd-dddddddd0001'
       and user_id = '00000000-0000-0000-0000-00000a000003' $$,
  'user can DELETE their own RSVP (cancel)'
);

select * from finish();

rollback;
