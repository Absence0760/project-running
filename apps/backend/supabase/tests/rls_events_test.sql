-- RLS suite for `public.events` base row-level policies.
--
-- Companion file. `rls_events_meet_point_test.sql` covers the
-- column-grant lockdown on `meet_lat` / `meet_lng` (20260723_001 +
-- 20260806_001 + 20260818_001 redo). This file pins the row-level
-- policies that govern who can read / create / update / delete an
-- event row.
--
-- Policy stack (per migrations 20260416_001, 20260428_001):
--   - SELECT "events readable with their club" — caller must see
--     the parent club (public / owner / active member).
--   - INSERT "organisers can create events" — `is_event_organiser`
--     (owner / admin / event_organiser) AND author_id = auth.uid.
--   - UPDATE "organisers can edit events" — `is_event_organiser`.
--   - DELETE "organisers can delete events" — `is_event_organiser`.
--
-- The `is_event_organiser` helper accepts roles `owner`, `admin`,
-- `event_organiser` but **excludes** `race_director` and `member`.
-- The race_director / event_organiser role split is the load-
-- bearing decision from 20260428_001 — directors arm + start +
-- end races but do not write events, organisers do the opposite.
-- A regression that widens is_event_organiser to include `member`
-- lets any joiner publish events under the club's name; a
-- regression that includes `race_director` collapses the role
-- split.

begin;

select plan(23);

-- ── Fixture ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000ff0001', 'authenticated', 'authenticated',
   'owner@event.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000ff0002', 'authenticated', 'authenticated',
   'organiser@event.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000ff0003', 'authenticated', 'authenticated',
   'director@event.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000ff0004', 'authenticated', 'authenticated',
   'member@event.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000ff0005', 'authenticated', 'authenticated',
   'stranger@event.local', '', now(), now());

-- Pre-role-switch fixture (bypasses RLS).
insert into clubs (id, owner_id, name, slug, is_public)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa0001',
   '00000000-0000-0000-0000-000000ff0001',
   'Event Test Club', 'event-test', false);

insert into club_members (club_id, user_id, role, status)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa0001',
   '00000000-0000-0000-0000-000000ff0002', 'event_organiser', 'active'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa0001',
   '00000000-0000-0000-0000-000000ff0003', 'race_director', 'active'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa0001',
   '00000000-0000-0000-0000-000000ff0004', 'member', 'active');

-- Plant a pre-existing event by the owner so SELECT / UPDATE /
-- DELETE tests have something to target.
insert into events (id, club_id, title, starts_at, author_id)
values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0001',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa0001',
   'Weekly Long Run',
   '2026-06-15 09:00:00+00',
   '00000000-0000-0000-0000-000000ff0001');

-- Event-level visibility fixture (20270113_001): a PUBLIC club holding a public
-- event AND a members-only (is_public = false) event, plus an attendee row and
-- an event-tied club_post on the members-only one — to pin that a public club
-- can hide an individual event from non-members, discovery, and every
-- event-delegating surface. ff0004 (the same member) is enrolled here too.
insert into clubs (id, owner_id, name, slug, is_public)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa0002',
   '00000000-0000-0000-0000-000000ff0001',
   'Public Event Club', 'public-event-test', true);

insert into club_members (club_id, user_id, role, status)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa0002',
   '00000000-0000-0000-0000-000000ff0004', 'member', 'active');

insert into events (id, club_id, title, starts_at, author_id, is_public)
values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0010',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa0002', 'Open Parkrun',
   '2026-08-01 09:00:00+00', '00000000-0000-0000-0000-000000ff0001', true),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0011',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa0002', 'Members Committee Meeting',
   '2026-08-02 18:00:00+00', '00000000-0000-0000-0000-000000ff0001', false);

insert into event_attendees (event_id, instance_start, user_id, status)
values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0011', '2026-08-02 18:00:00+00',
   '00000000-0000-0000-0000-000000ff0004', 'going');

insert into club_posts (id, club_id, event_id, author_id, body)
values
  ('dddddddd-dddd-dddd-dddd-dddddddd0011',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa0002',
   'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0011',
   '00000000-0000-0000-0000-000000ff0001',
   'Agenda for the members-only meeting');

-- Price BOTH events (bypass the charges_enabled trigger for the fixture) to pin
-- that event_pricing — gated on the SECURITY DEFINER is_event_visible helper,
-- which does NOT inherit the events RLS — also honours event-level visibility.
set session_replication_role = replica;
insert into event_pricing (event_id, price_cents, currency)
values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0010', 1000, 'usd'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0011', 2000, 'usd');
set session_replication_role = origin;

set local role authenticated;

-- 1. Active member can SELECT events in their private club.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ff0004"}';
select results_eq(
  $$ select title from events
     where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0001' $$,
  $$ values ('Weekly Long Run'::text) $$,
  'active member can SELECT events in their private club'
);

-- 2. Stranger cannot SELECT events of a private club they do not
--    belong to.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ff0005"}';
select is_empty(
  $$ select id from events
     where club_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa0001' $$,
  'stranger cannot SELECT events of a private club they do not belong to'
);

-- 3. Event organiser can INSERT an event under their own user_id.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ff0002"}';
insert into events (id, club_id, title, starts_at, author_id)
values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0002',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa0001',
   'Organiser-scheduled Race',
   '2026-07-01 09:00:00+00',
   '00000000-0000-0000-0000-000000ff0002');
select results_eq(
  $$ select count(*)::int from events
     where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0002' $$,
  $$ values (1) $$,
  'event_organiser can INSERT a new event (positive control)'
);

-- 4. Plain member cannot INSERT an event (is_event_organiser
--    excludes role='member').
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ff0004"}';
select throws_ok(
  $$ insert into events (club_id, title, starts_at, author_id)
       values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa0001',
               'Member Hijack',
               '2026-07-15 09:00:00+00',
               '00000000-0000-0000-0000-000000ff0004') $$,
  '42501',
  null,
  'plain member cannot INSERT an event (is_event_organiser excludes member)'
);

-- 5. Race director CANNOT INSERT an event — the 20260428_001 role
--    split means race_director arms races but does NOT publish
--    events. Pinned explicitly so a future widening of
--    is_event_organiser to include race_director gets caught.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ff0003"}';
select throws_ok(
  $$ insert into events (club_id, title, starts_at, author_id)
       values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa0001',
               'Director Encroachment',
               '2026-07-22 09:00:00+00',
               '00000000-0000-0000-0000-000000ff0003') $$,
  '42501',
  null,
  'race_director cannot INSERT an event (role split with event_organiser)'
);

-- 6. Forged author_id INSERT rejected even when the caller is
--    a legitimate organiser.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ff0002"}';
select throws_ok(
  $$ insert into events (club_id, title, starts_at, author_id)
       values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa0001',
               'Forged Attribution',
               '2026-07-29 09:00:00+00',
               '00000000-0000-0000-0000-000000ff0001') $$,
  '42501',
  null,
  'organiser cannot INSERT an event under another user_id'
);

-- 7. Event organiser can UPDATE an event (even one created by
--    someone else — the policy gates on the role, not authorship).
update events set title = 'Renamed By Organiser'
  where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0001';
select results_eq(
  $$ select title from events
     where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0001' $$,
  $$ values ('Renamed By Organiser'::text) $$,
  'event_organiser can UPDATE an event (any author, role-gated not author-gated)'
);

-- 8. Plain member UPDATE is a silent no-op.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ff0004"}';
update events set title = 'Pwned By Member'
  where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0001';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ff0002"}';
select results_eq(
  $$ select title from events
     where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0001' $$,
  $$ values ('Renamed By Organiser'::text) $$,
  'plain member UPDATE on an event is a no-op'
);

-- 9. Event organiser can DELETE; plain member cannot (combined in
--    one test — try the member delete first, assert row survives,
--    then organiser delete and assert empty).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ff0004"}';
delete from events where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0002';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ff0002"}';
delete from events where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0002';
select is_empty(
  $$ select id from events
     where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0002' $$,
  'plain member DELETE is a no-op; event_organiser DELETE succeeds'
);

-- ── Event-level visibility: PUBLIC club, members-only event (20270113_001) ──

-- 10. A non-member CAN see a public event in a public club (positive control).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ff0005"}';
select results_eq(
  $$ select title from events where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0010' $$,
  $$ values ('Open Parkrun'::text) $$,
  'non-member sees a PUBLIC event in a public club'
);

-- 11. A non-member CANNOT see a members-only event in the same public club.
select is_empty(
  $$ select id from events where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0011' $$,
  'non-member cannot see a members-only event in a public club'
);

-- 12. An active member CAN see the members-only event.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ff0004"}';
select results_eq(
  $$ select title from events where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0011' $$,
  $$ values ('Members Committee Meeting'::text) $$,
  'active member sees the members-only event'
);

-- 13. A non-member cannot read the members-only event's attendees
--     (event_attendees inherits events SELECT RLS via its exists(...from events) gate).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ff0005"}';
select is_empty(
  $$ select user_id from event_attendees where event_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0011' $$,
  'non-member cannot read a members-only event''s attendees'
);

-- 14. A member CAN read the members-only event's attendees.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ff0004"}';
select results_eq(
  $$ select count(*)::int from event_attendees where event_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0011' $$,
  $$ values (1) $$,
  'member can read a members-only event''s attendees'
);

-- 15. A non-member cannot read a club_post tied to the members-only event
--     (club_posts SELECT re-gated to inherit event visibility, 20270113_001).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ff0005"}';
select is_empty(
  $$ select id from club_posts where id = 'dddddddd-dddd-dddd-dddd-dddddddd0011' $$,
  'non-member cannot read a club_post tied to a members-only event'
);

-- 16. A member CAN read that event-tied post.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ff0004"}';
select results_eq(
  $$ select count(*)::int from club_posts where id = 'dddddddd-dddd-dddd-dddd-dddddddd0011' $$,
  $$ values (1) $$,
  'member can read a club_post tied to a members-only event'
);

-- 17-18. Discovery (anon): the public event surfaces, the members-only event is excluded.
-- Clear the JWT claims too — `set role anon` alone leaves request.jwt.claims set
-- from the prior member assertion, so auth.uid() would still resolve to a member.
set local role anon;
set local "request.jwt.claims" = '{}';
select results_eq(
  $$ select count(*)::int from search_public_events() where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0010' $$,
  $$ values (1) $$,
  'discovery surfaces a public event in a public club'
);
select is(
  (select count(*)::int from search_public_events() where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0011'),
  0,
  'discovery excludes a members-only event'
);

-- 19. Anon direct read also cannot see the members-only event.
select is_empty(
  $$ select id from events where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0011' $$,
  'anon cannot read a members-only event directly'
);

-- 20. The club OWNER can see the members-only event (enroll_club_owner enrols
--     them as an 'owner' club_members row, so private.is_club_member covers them).
--     Pins the owner path so a regression dropping that trigger gets caught.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ff0001"}';
select results_eq(
  $$ select title from events where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0011' $$,
  $$ values ('Members Committee Meeting'::text) $$,
  'club owner sees the members-only event'
);

-- 21. A non-member CAN read pricing for a PUBLIC event (positive control —
--     proves the is_event_visible tightening did not over-restrict).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ff0005"}';
select results_eq(
  $$ select price_cents from event_pricing where event_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0010' $$,
  $$ values (1000) $$,
  'non-member can read pricing for a public event'
);

-- 22. A non-member CANNOT read pricing for the members-only event
--     (event_pricing gates on is_event_visible, now event-visibility-aware).
select is_empty(
  $$ select price_cents from event_pricing where event_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0011' $$,
  'non-member cannot read pricing for a members-only event'
);

-- 23. A member CAN read pricing for the members-only event (so they can register).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000ff0004"}';
select results_eq(
  $$ select price_cents from event_pricing where event_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0011' $$,
  $$ values (2000) $$,
  'member can read pricing for a members-only event'
);

select * from finish();

rollback;
