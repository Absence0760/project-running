-- Pins migration 20261025_001 — event photo gallery RLS (social-group
-- persona #49). The gallery's whole point: a photo tagged to an event is
-- visible to anyone who can see the event, EVEN when the underlying run
-- is private. Also asserts a non-event photo on a private run stays
-- hidden from non-owners.

begin;
select plan(4);

insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                        instance_id, aud, role)
values
  ('99999999-9999-9999-9999-9999000049a1', 'owner-49@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('99999999-9999-9999-9999-9999000049b2', 'viewer-49@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
on conflict (id) do nothing;

-- A public club + event the viewer can see.
insert into clubs (id, owner_id, name, slug, is_public, join_policy)
values ('dddddddd-0000-0000-0000-0000000049c1',
        '99999999-9999-9999-9999-9999000049a1',
        'Gallery Club', 'gallery-club-49', true, 'open')
on conflict (id) do nothing;

insert into events (id, club_id, title, starts_at, created_by)
values ('eeeeeeee-0000-0000-0000-0000000049e1',
        'dddddddd-0000-0000-0000-0000000049c1',
        'Gallery 10K', '2026-06-20T08:00:00Z',
        '99999999-9999-9999-9999-9999000049a1');

-- Owner's PRIVATE run (is_public=false) at the event.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, metadata)
values ('aaaaaaaa-0000-0000-0000-0000000049f1',
        '99999999-9999-9999-9999-9999000049a1',
        '2026-06-20T08:00:00Z', 10000, 2700, 'app', false, '{"activity_type":"run"}');

-- One event-tagged photo + one plain photo, both on the private run.
insert into run_photos (id, run_id, owner_id, storage_path, position_idx, event_id, event_instance_start)
values ('11111111-0000-0000-0000-0000000049a1',
        'aaaaaaaa-0000-0000-0000-0000000049f1',
        '99999999-9999-9999-9999-9999000049a1',
        '99999999-9999-9999-9999-9999000049a1/g1.jpg', 0,
        'eeeeeeee-0000-0000-0000-0000000049e1', '2026-06-20T08:00:00Z');
insert into run_photos (id, run_id, owner_id, storage_path, position_idx)
values ('22222222-0000-0000-0000-0000000049b2',
        'aaaaaaaa-0000-0000-0000-0000000049f1',
        '99999999-9999-9999-9999-9999000049a1',
        '99999999-9999-9999-9999-9999000049a1/p2.jpg', 1);

-- ── as the viewer (NOT the run owner) ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-9999000049b2","role":"authenticated"}';

select is(
  (select count(*)::int from run_photos
   where id = '11111111-0000-0000-0000-0000000049a1'),
  1,
  'event-tagged photo is visible to a non-owner who can see the event');

select is(
  (select count(*)::int from run_photos
   where id = '22222222-0000-0000-0000-0000000049b2'),
  0,
  'a plain photo on a private run stays hidden from non-owners');

select is(
  (select count(*)::int from run_photos
   where event_id = 'eeeeeeee-0000-0000-0000-0000000049e1'),
  1,
  'gallery query returns exactly the one event-tagged photo');

-- ── as the owner ──
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-9999000049a1","role":"authenticated"}';
select is(
  (select count(*)::int from run_photos
   where run_id = 'aaaaaaaa-0000-0000-0000-0000000049f1'),
  2,
  'the owner still sees both photos on their own run');

select * from finish();
rollback;
