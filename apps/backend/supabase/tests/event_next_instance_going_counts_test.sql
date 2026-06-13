-- event_next_instance_going_counts RPC (migration 20270122_001).
--
-- The RPC pairs each event id with its next-instance timestamp and counts
-- only the status='going' attendees at that exact (event_id, instance_start),
-- so the events list gets one integer per event instead of every all-time
-- 'going' row. Asserts: per-event scoping to the supplied next instance, that
-- a different instance / non-going status is excluded, and that an event with
-- no going RSVPs at its next instance returns 0 (left join keeps the row).
--
-- Driven as service_role so RLS visibility isn't the thing under test — the
-- count math is. The capacity trigger demotes over-cap 'going' to
-- 'waitlisted', so these events are left uncapped (capacity NULL) to keep the
-- inserted statuses verbatim.

begin;

select plan(4);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01', 'authenticated', 'authenticated', 'g1@cnt.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa02', 'authenticated', 'authenticated', 'g2@cnt.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa03', 'authenticated', 'authenticated', 'g3@cnt.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public)
values ('cccccccc-cccc-cccc-cccc-cccccccccc01',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01', 'Count Club', 'count-club', true);

insert into events (id, club_id, title, starts_at, author_id, capacity)
values
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01',
   'cccccccc-cccc-cccc-cccc-cccccccccc01', 'Recurring Run',
   '2026-07-01 09:00:00+00', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01', null),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee02',
   'cccccccc-cccc-cccc-cccc-cccccccccc01', 'Quiet Run',
   '2026-07-01 09:00:00+00', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01', null);

-- Event 01: two 'going' at the NEXT instance (2026-07-08), one 'going' at a
-- PRIOR instance (2026-07-01), and one 'maybe' at the next instance.
insert into event_attendees (event_id, user_id, status, instance_start) values
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01', 'going', '2026-07-08 09:00:00+00'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa02', 'going', '2026-07-08 09:00:00+00'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa03', 'going', '2026-07-01 09:00:00+00'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa03', 'maybe', '2026-07-08 09:00:00+00');

-- The next instance (08th) counts exactly the two going there; the prior
-- instance's going and the next instance's maybe are both excluded.
select is(
  (select going_count from event_next_instance_going_counts(
     array['eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01']::uuid[],
     array['2026-07-08 09:00:00+00']::timestamptz[])
   where event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01'),
  2::bigint,
  'counts only going at the supplied next instance (prior instance + maybe excluded)');

-- Asking for the PRIOR instance returns just the one going there — proves the
-- count is scoped to the timestamp passed in, not all-time.
select is(
  (select going_count from event_next_instance_going_counts(
     array['eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01']::uuid[],
     array['2026-07-01 09:00:00+00']::timestamptz[])
   where event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01'),
  1::bigint,
  'count is scoped to the passed instance timestamp, not all-time');

-- Event 02 has no going RSVPs at its next instance: left join keeps the row at 0.
select is(
  (select going_count from event_next_instance_going_counts(
     array['eeeeeeee-eeee-eeee-eeee-eeeeeeeeee02']::uuid[],
     array['2026-07-08 09:00:00+00']::timestamptz[])
   where event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee02'),
  0::bigint,
  'an event with no going RSVPs at its next instance returns 0');

-- Multiple events in one call: each is paired with ITS own next-instance
-- timestamp by ordinality, not cross-joined.
select results_eq(
  $q$ select event_id, going_count from event_next_instance_going_counts(
        array['eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01',
              'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee02']::uuid[],
        array['2026-07-08 09:00:00+00',
              '2026-07-08 09:00:00+00']::timestamptz[])
      order by event_id $q$,
  $q$ values ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01'::uuid, 2::bigint),
             ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee02'::uuid, 0::bigint) $q$,
  'each event is paired with its own next-instance timestamp by ordinality');

select * from finish();

rollback;
