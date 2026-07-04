-- Pins migration 20270318_001: the public-link helper functions behind
-- public_runs / public_routes answer false for shadow-hidden targets (and
-- is_public_event_by_id also honours the event-level is_public gate from
-- 20270113_001), so an auto-hidden route / club / event id can't keep
-- leaking through the public views' link columns.

begin;

select plan(8);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000318a1', 'authenticated', 'authenticated',
   'owner@shadow.local', '', now(), now());

insert into routes (id, user_id, name, waypoints, distance_m, is_public)
values
  ('03180318-0318-0318-0318-0318031803a1'::uuid,
   '00000000-0000-0000-0000-0000000318a1', 'Shadow Route', '[]'::jsonb, 5000, true);

insert into clubs (id, owner_id, name, slug, is_public)
values
  ('03180318-0318-0318-0318-0318031803c1'::uuid,
   '00000000-0000-0000-0000-0000000318a1', 'Shadow Club', 'shadow-club', true);

insert into events (id, club_id, title, starts_at, author_id, is_public)
values
  ('03180318-0318-0318-0318-0318031803e1'::uuid,
   '03180318-0318-0318-0318-0318031803c1', 'Shadow Event',
   now() + interval '7 days', '00000000-0000-0000-0000-0000000318a1', true);

select is(is_public_route_by_id('03180318-0318-0318-0318-0318031803a1'::uuid), true,
  'a public, un-hidden route reports public');
select is(is_public_club_by_id('03180318-0318-0318-0318-0318031803c1'::uuid), true,
  'a public, un-hidden club reports public');
select is(is_public_event_by_id('03180318-0318-0318-0318-0318031803e1'::uuid), true,
  'a public event in a public, un-hidden club reports public');

update routes set shadow_hidden = true
  where id = '03180318-0318-0318-0318-0318031803a1';
select is(is_public_route_by_id('03180318-0318-0318-0318-0318031803a1'::uuid), false,
  'a shadow-hidden route no longer reports public');

update clubs set shadow_hidden = true
  where id = '03180318-0318-0318-0318-0318031803c1';
select is(is_public_club_by_id('03180318-0318-0318-0318-0318031803c1'::uuid), false,
  'a shadow-hidden club no longer reports public');
select is(is_public_event_by_id('03180318-0318-0318-0318-0318031803e1'::uuid), false,
  'an event in a shadow-hidden club no longer reports public');

update clubs set shadow_hidden = false
  where id = '03180318-0318-0318-0318-0318031803c1';
update events set is_public = false
  where id = '03180318-0318-0318-0318-0318031803e1';
select is(is_public_event_by_id('03180318-0318-0318-0318-0318031803e1'::uuid), false,
  'a members-only event (is_public=false) in a public club is not link-public');

select is(is_public_route_by_id(null), false,
  'a null route id reports false, not null');

select * from finish();
rollback;
