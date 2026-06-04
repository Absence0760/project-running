-- Pin the column-level revoke on `events.meet_lat` / `events.meet_lng`
-- from migration 20260723_001_events_meet_point_anon_revoke.sql AND
-- the follow-up tightening 20260806_001_events_meet_point_authenticated_revoke.sql.
--
-- The original (pass-2) finding: an organiser using their home as
-- the meet point would leak those coordinates to anon viewers of a
-- public-club event. 20260723_001 closed the anon side. /audit/all
-- pass 4 surfaced that authenticated non-members could still scrape
-- the same columns, so 20260806_001 extended the same revoke shape
-- to `authenticated` (no render path reads meet_lat/meet_lng today —
-- they were stored for a future map-pin feature, so the wire-format
-- tightening has no UI dependency).
--
-- This test pins the post-tightening contract:
--   - anon SELECT on (meet_lat, meet_lng) raises 42501
--   - authenticated SELECT on (meet_lat, meet_lng) raises 42501 too
--   - both roles still read meet_label (canonical display field)

begin;

select plan(4);

-- Fixture: one public club, one event with a meeting point set.
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000ee01', 'authenticated', 'authenticated',
   'organiser@meet.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000ee02', 'authenticated', 'authenticated',
   'attendee@meet.local', '', now(), now());

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ee01"}';

insert into clubs (id, owner_id, name, slug, is_public)
values ('55555555-5555-5555-5555-555555555501',
        '00000000-0000-0000-0000-00000000ee01',
        'Public Meet Test', 'public-meet-test', true);

insert into events (id, club_id, title, starts_at, meet_lat, meet_lng, meet_label, author_id)
values ('55555555-5555-5555-5555-555555555502',
        '55555555-5555-5555-5555-555555555501',
        'Sunday Long Run',
        now() + interval '2 days',
        51.5074, -0.1278,
        'Trafalgar Square fountain',
        '00000000-0000-0000-0000-00000000ee01');

-- 1. Authenticated SELECT on meet_lat / meet_lng raises 42501 —
--    the 20260806_001 tightening closed the non-member leak.
--    Re-authenticate as a non-organiser to cover the public-club
--    "non-member authenticated viewer" case.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ee02","role":"authenticated"}';

select throws_ok(
  $$ select meet_lat, meet_lng from events
     where id = '55555555-5555-5555-5555-555555555502' $$,
  '42501',
  null,
  'authenticated non-member SELECT on meet_lat / meet_lng raises permission denied'
);

-- 2. Authenticated callers still see meet_label too.
select results_eq(
  $$ select meet_label from events
     where id = '55555555-5555-5555-5555-555555555502' $$,
  $$ values ('Trafalgar Square fountain') $$,
  'authenticated callers read meet_label'
);

-- ── Anon ──
set local role anon;
set local "request.jwt.claims" = '';

-- 3. Anon SELECT on the precise coordinates raises 42501.
select throws_ok(
  $$ select meet_lat, meet_lng from events
     where id = '55555555-5555-5555-5555-555555555502' $$,
  '42501',
  null,
  'anon SELECT on meet_lat / meet_lng raises permission denied'
);

-- 4. Anon SELECT on meet_label still works — the canonical text
--    display field is unchanged.
select results_eq(
  $$ select meet_label from events
     where id = '55555555-5555-5555-5555-555555555502' $$,
  $$ values ('Trafalgar Square fountain') $$,
  'anon SELECT on meet_label still works (only precise coords gated)'
);

select * from finish();

rollback;
