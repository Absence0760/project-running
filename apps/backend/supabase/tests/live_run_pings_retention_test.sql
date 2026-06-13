-- Pins the live_run_pings retention boundary: cleanup_stale_live_run_pings()
-- (20270119_001) reaps pings older than 48h and keeps everything inside it.
--
-- The original 4h cutoff (20260509_001) deleted the live feed mid-run for any
-- ultra. The boundary is now 48h to match race_pings (20261213_001). Seed one
-- ping just inside the window (47h59m old -> must survive) and one well past it
-- (72h old -> must be reaped), call the cleanup, and assert the split.
--
-- Runs as superuser so the spectator-visibility RLS is out of the way — the
-- assertion is the purge boundary, not RLS.

begin;

select plan(3);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000ee01', 'authenticated', 'authenticated',
   'retain@ping.local', '', now(), now());

insert into runs (id, user_id, started_at, duration_s, distance_m, source, metadata, is_public)
values
  ('33333333-3333-3333-3333-33330000ee01',
   '00000000-0000-0000-0000-00000000ee01',
   now(), 1800, 5000, 'app', '{"activity_type":"run"}', false);

insert into live_run_pings (run_id, user_id, at, lat, lng)
values
  -- Just inside the 48h window: must survive.
  ('33333333-3333-3333-3333-33330000ee01',
   '00000000-0000-0000-0000-00000000ee01',
   now() - interval '47 hours 59 minutes', 47.37, 8.54),
  -- Well past the cutoff: must be reaped.
  ('33333333-3333-3333-3333-33330000ee01',
   '00000000-0000-0000-0000-00000000ee01',
   now() - interval '72 hours', 47.38, 8.55);

select is(
  (select cleanup_stale_live_run_pings()),
  1,
  'cleanup_stale_live_run_pings purges exactly the one ping past the 48h cutoff'
);
select is(
  (select count(*)::int from live_run_pings
     where run_id = '33333333-3333-3333-3333-33330000ee01'),
  1,
  'the ping at 47h59m (inside the 48h window) survives'
);
select is(
  (select at < now() - interval '48 hours' from live_run_pings
     where run_id = '33333333-3333-3333-3333-33330000ee01' limit 1),
  false,
  'no ping older than the 48h cutoff remains'
);

select * from finish();
rollback;
