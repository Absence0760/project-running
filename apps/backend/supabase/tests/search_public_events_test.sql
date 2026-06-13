-- Pins migration 20270110_001 — search_public_events is the cross-club activity
-- discovery RPC. It is `security invoker` + scoped to `clubs.is_public = true`,
-- so the load-bearing property is: a PUBLIC club's events surface to anyone, a
-- PRIVATE club's events never do (no SECURITY DEFINER leak). Also pins the
-- category / weekday / paid filters that back the /social Discover tab.

begin;
select plan(10);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('aaaaaaaa-0000-0000-0000-0000000000d1', 'authenticated', 'authenticated', 'spe@disc.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public)
values
  ('cccccccc-0000-0000-0000-0000000000f1', 'aaaaaaaa-0000-0000-0000-0000000000d1', 'Public Disc Club', 'public-disc', true),
  ('cccccccc-0000-0000-0000-0000000000f2', 'aaaaaaaa-0000-0000-0000-0000000000d1', 'Private Disc Club', 'private-disc', false);

-- Public club: a free weekly Sunday run + a paid weekly Sunday pilates class.
insert into events (id, club_id, author_id, title, category, discipline, starts_at, recurrence_freq, recurrence_byday)
values
  ('eeeeeeee-0000-0000-0000-0000000000a1', 'cccccccc-0000-0000-0000-0000000000f1',
   'aaaaaaaa-0000-0000-0000-0000000000d1', 'Sunday Long Run', 'run', null,
   now() + interval '2 days', 'weekly', array['SU']),
  ('eeeeeeee-0000-0000-0000-0000000000a2', 'cccccccc-0000-0000-0000-0000000000f1',
   'aaaaaaaa-0000-0000-0000-0000000000d1', 'Reformer Pilates', 'class', 'Reformer Pilates',
   now() + interval '3 days', 'weekly', array['SU']),
  -- Private club: a class that must NEVER appear in discovery.
  ('eeeeeeee-0000-0000-0000-0000000000a3', 'cccccccc-0000-0000-0000-0000000000f2',
   'aaaaaaaa-0000-0000-0000-0000000000d1', 'Secret Class', 'class', 'Secret',
   now() + interval '2 days', 'weekly', array['SU']);

-- Public, timezone-anchored: 23:00 UTC = 19:00 America/New_York (EDT) -> evening.
insert into events (id, club_id, author_id, title, category, discipline, starts_at, timezone, recurrence_freq, recurrence_byday)
values
  ('eeeeeeee-0000-0000-0000-0000000000a4', 'cccccccc-0000-0000-0000-0000000000f1',
   'aaaaaaaa-0000-0000-0000-0000000000d1', 'Evening Pilates', 'class', 'Evening Pilates',
   timestamptz '2026-07-05 23:00:00+00', 'America/New_York', 'weekly', array['SU']);

-- Price the public pilates class (bypass the charges_enabled trigger for the fixture).
set session_replication_role = replica;
insert into event_pricing (event_id, price_cents, currency)
values ('eeeeeeee-0000-0000-0000-0000000000a2', 1500, 'usd');
set session_replication_role = origin;

-- Call as anon — discovery must work logged-out.
set local role anon;

select lives_ok(
  $$ select * from search_public_events() $$,
  'search_public_events executes for anon');

select is(
  (select count(*)::int from search_public_events() where id = 'eeeeeeee-0000-0000-0000-0000000000a1'),
  1, 'a public club event is discoverable');

select is(
  (select count(*)::int from search_public_events() where id = 'eeeeeeee-0000-0000-0000-0000000000a3'),
  0, 'a PRIVATE club event is never discoverable');

select is(
  (select count(*)::int from search_public_events(p_category := 'class')
     where id = 'eeeeeeee-0000-0000-0000-0000000000a2'),
  1, 'category=class returns the class');

select is(
  (select count(*)::int from search_public_events(p_category := 'class')
     where id = 'eeeeeeee-0000-0000-0000-0000000000a1'),
  0, 'category=class excludes the run');

select is(
  (select count(*)::int from search_public_events(p_byday := 'SU')
     where id = 'eeeeeeee-0000-0000-0000-0000000000a1'),
  1, 'byday=SU matches a weekly Sunday event');

select is(
  (select count(*)::int from search_public_events(p_paid := 'paid')
     where id = 'eeeeeeee-0000-0000-0000-0000000000a2'),
  1, 'paid filter returns the priced class');

select is(
  (select count(*)::int from search_public_events(p_paid := 'free')
     where id = 'eeeeeeee-0000-0000-0000-0000000000a2'),
  0, 'free filter excludes the priced class');

-- Time-of-day is the event's LOCAL hour (19:00 New York), not the 23:00 UTC instant.
select is(
  (select count(*)::int from search_public_events(p_time := 'evening')
     where id = 'eeeeeeee-0000-0000-0000-0000000000a4'),
  1, 'evening filter matches a 19:00-local (23:00 UTC) event');

select is(
  (select count(*)::int from search_public_events(p_time := 'morning')
     where id = 'eeeeeeee-0000-0000-0000-0000000000a4'),
  0, 'morning filter excludes the 19:00-local event (not its 23:00 UTC hour)');

select * from finish();
rollback;
