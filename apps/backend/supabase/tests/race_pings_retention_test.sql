-- Pins F5: race_pings has a retention purge (cleanup_stale_race_pings,
-- 20261213_001) mirroring live_run_pings.
--
-- Seed one stale ping (older than the 48h cutoff) and one fresh ping,
-- call the cleanup, and assert the stale one is gone and the fresh one
-- survives. Runs as superuser so the spectator-visibility RLS is out of
-- the way — the assertion is the purge function, not RLS.

begin;

select plan(3);

-- Fixtures: a club + event (race_pings.event_id FKs to events).
insert into clubs (id, owner_id, name, slug)
  values ('c1aaaaaa-0000-0000-0000-0000000f0501',
          'a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Race Club', 'race-club-f5');
insert into events (id, club_id, title, starts_at, author_id)
  values ('e1aaaaaa-0000-0000-0000-0000000f0501',
          'c1aaaaaa-0000-0000-0000-0000000f0501', 'Race Event',
          now(), 'a1b2c3d4-e5f6-7890-abcd-ef1234567890');

insert into race_pings (event_id, instance_start, user_id, at, lat, lng)
values
  ('e1aaaaaa-0000-0000-0000-0000000f0501', now(),
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890', now() - interval '72 hours', 1.0, 2.0),
  ('e1aaaaaa-0000-0000-0000-0000000f0501', now(),
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890', now() - interval '1 hour', 3.0, 4.0);

select is(
  (select cleanup_stale_race_pings()),
  1,
  'cleanup_stale_race_pings purges exactly the one stale ping'
);
select is(
  (select count(*)::int from race_pings
     where event_id = 'e1aaaaaa-0000-0000-0000-0000000f0501'),
  1,
  'the fresh ping survives the sweep'
);
select is(
  (select at < now() - interval '48 hours' from race_pings
     where event_id = 'e1aaaaaa-0000-0000-0000-0000000f0501' limit 1),
  false,
  'no ping older than the 48h cutoff remains'
);

select * from finish();
rollback;
