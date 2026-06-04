-- Persona-hunt social-group #10: the `get_event_meet_point(uuid)`
-- SECURITY DEFINER RPC unlocks the meetup coordinates that are
-- otherwise column-revoked from every client role (see
-- rls_events_meet_point_test.sql + migrations 20260723_001 /
-- 20260806_001). This pins the membership gate:
--   - an active member of the event's club gets the coords
--   - an authenticated non-member gets NO rows
--   - anon executes but gets NO rows (the in-function membership gate,
--     not an EXECUTE revoke, is the authorization boundary)
--   - a member of an event with no coords set gets NO rows

begin;

select plan(5);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000fee01', 'authenticated', 'authenticated',
   'mp-owner@meet.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000fee02', 'authenticated', 'authenticated',
   'mp-member@meet.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000fee03', 'authenticated', 'authenticated',
   'mp-stranger@meet.local', '', now(), now());

-- Fixtures run as the default (superuser) role so RLS on clubs /
-- club_members doesn't gate the seed — the assertions below switch to
-- authenticated / anon.
insert into clubs (id, owner_id, name, slug, is_public)
values ('66666666-6666-6666-6666-666666666601',
        '00000000-0000-0000-0000-0000000fee01',
        'Meet RPC Test', 'meet-rpc-test', true);

-- The owner is auto-added as a member by a trigger; explicitly add a
-- second active member, and leave the stranger out entirely.
insert into club_members (club_id, user_id, role, status)
values ('66666666-6666-6666-6666-666666666601',
        '00000000-0000-0000-0000-0000000fee02', 'member', 'active')
on conflict do nothing;

insert into events (id, club_id, title, starts_at, meet_lat, meet_lng, meet_label, author_id)
values
  ('66666666-6666-6666-6666-666666666602',
   '66666666-6666-6666-6666-666666666601',
   'Sunday Long Run', now() + interval '2 days',
   51.5074, -0.1278, 'Trafalgar Square fountain',
   '00000000-0000-0000-0000-0000000fee01'),
  ('66666666-6666-6666-6666-666666666603',
   '66666666-6666-6666-6666-666666666601',
   'Coordless Run', now() + interval '3 days',
   null, null, 'Somewhere vague',
   '00000000-0000-0000-0000-0000000fee01');

-- 1. Active member gets the coordinates.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000fee02","role":"authenticated"}';
select results_eq(
  $$ select meet_lat, meet_lng
     from get_event_meet_point('66666666-6666-6666-6666-666666666602') $$,
  $$ values (51.5074::double precision, -0.1278::double precision) $$,
  'active club member reads the meetup coordinates via the RPC'
);

-- 2. Member of an event with no coords set gets no rows.
select is_empty(
  $$ select * from get_event_meet_point('66666666-6666-6666-6666-666666666603') $$,
  'member of a coord-less event gets no rows'
);

-- 3. Authenticated non-member gets no rows.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000fee03","role":"authenticated"}';
select is_empty(
  $$ select * from get_event_meet_point('66666666-6666-6666-6666-666666666602') $$,
  'authenticated non-member gets no rows from the RPC'
);

-- 4. The non-member still cannot read the raw columns either.
select throws_ok(
  $$ select meet_lat, meet_lng from events
     where id = '66666666-6666-6666-6666-666666666602' $$,
  '42501',
  null,
  'non-member raw-column SELECT still raises permission denied'
);

-- 5. Anon executes the function but the membership gate returns no rows.
set local role anon;
set local "request.jwt.claims" = '';
select is_empty(
  $$ select * from get_event_meet_point('66666666-6666-6666-6666-666666666602') $$,
  'anon executes but the membership gate returns no rows'
);

select * from finish();

rollback;
