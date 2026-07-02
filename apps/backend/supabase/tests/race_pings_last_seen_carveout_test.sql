-- pgtap suite for the privacy-vs-safety carve-out on race_pings
-- (migration 20270309_001), the event-leaderboard analogue of the
-- live_run_pings carve-out (20270121_001).
--
-- Background: 20260704_001 dropped any in-zone race ping outright, so a
-- runner who stops inside their own privacy zone vanishes from the race
-- leaderboard + spectator feed. The carve-out keeps the SINGLE
-- most-recent in-zone ping per runner-per-race-instance, coarsened to a
-- ~2-dp grid (~1 km) and flagged coarse=true; older in-zone coarse pings
-- are replaced, not accumulated; out-of-zone pings are untouched.
--
-- A regression here is a privacy/safety failure in BOTH directions: a
-- precise in-zone point reaching the feed leaks the home address; a
-- dropped last-seen makes a stopped runner invisible on the board.

begin;

select plan(10);

-- ── Fixture: a public club + race, one runner with a privacy zone ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000006c1', 'authenticated', 'authenticated',
   'race-sar@carveout.local', '', now(), now());

set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"00000000-0000-0000-0000-0000000006c1","role":"authenticated"}';

insert into clubs (id, owner_id, name, slug, is_public)
values ('55555555-5555-5555-5555-555555555501',
        '00000000-0000-0000-0000-0000000006c1',
        'Race Carveout Club', 'race-carveout', true);

insert into events (id, club_id, title, starts_at, author_id)
values ('55555555-5555-5555-5555-555555555502',
        '55555555-5555-5555-5555-555555555501',
        'Race Carveout Test', now(),
        '00000000-0000-0000-0000-0000000006c1');

insert into race_sessions (event_id, instance_start, status, started_at)
values ('55555555-5555-5555-5555-555555555502',
        '2026-07-04 10:00:00+00', 'running', now());

-- Zone: ~150 m radius around (47.37, 8.54).
insert into user_settings (user_id, prefs)
values (
  '00000000-0000-0000-0000-0000000006c1',
  jsonb_build_object(
    'privacy_zones', jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.54, 'radius_m', 150)
    )
  )
);

-- ── privacy_coarsen_coord (shared helper internals) ──
reset role;

-- 1. Coarsens to 2 decimal places.
select is(
  privacy_coarsen_coord(47.376123),
  47.38::double precision,
  'privacy_coarsen_coord rounds to 2 decimal places'
);

-- 2. The coarsened value drops sub-2-dp precision (no exact leak).
select isnt(
  privacy_coarsen_coord(8.54199),
  8.54199::double precision,
  'privacy_coarsen_coord drops sub-2-dp precision'
);

set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"00000000-0000-0000-0000-0000000006c1","role":"authenticated"}';

-- ── In-zone ping is stored coarsened, never precise ──
-- 3. A precise in-zone ping (near the zone centre) lands as exactly one
--    coarse row — NOT dropped (the old behaviour), NOT stored precise.
insert into race_pings (event_id, instance_start, user_id, at, lat, lng)
values (
  '55555555-5555-5555-5555-555555555502',
  '2026-07-04 10:00:00+00',
  '00000000-0000-0000-0000-0000000006c1',
  now(), 47.370001, 8.540001
);

select is(
  (select count(*)::int from race_pings
     where user_id = '00000000-0000-0000-0000-0000000006c1'),
  1,
  'in-zone race ping is retained (not dropped) as a coarse last-seen'
);

-- 4. The stored ping is flagged coarse.
select is(
  (select coarse from race_pings
     where user_id = '00000000-0000-0000-0000-0000000006c1'),
  true,
  'retained in-zone race ping is flagged coarse = true'
);

-- 5. The stored lat/lng are coarsened to the 2-dp grid, not the precise
--    input — the exact home point never reaches the leaderboard/feed.
select is(
  (select lat from race_pings
     where user_id = '00000000-0000-0000-0000-0000000006c1'),
  47.37::double precision,
  'retained in-zone race ping lat is coarsened to 2 dp'
);
select is(
  (select lng from race_pings
     where user_id = '00000000-0000-0000-0000-0000000006c1'),
  8.54::double precision,
  'retained in-zone race ping lng is coarsened to 2 dp'
);

-- ── A second in-zone ping REPLACES the coarse last-seen ──
-- 6. Inserting another in-zone ping leaves still exactly one coarse row
--    for this runner — it replaces, not accumulates.
insert into race_pings (event_id, instance_start, user_id, at, lat, lng)
values (
  '55555555-5555-5555-5555-555555555502',
  '2026-07-04 10:00:00+00',
  '00000000-0000-0000-0000-0000000006c1',
  now(), 47.370900, 8.539200
);

select is(
  (select count(*)::int from race_pings
     where user_id = '00000000-0000-0000-0000-0000000006c1'),
  1,
  'a second in-zone race ping replaces the coarse last-seen (no accumulation)'
);

-- ── Out-of-zone pings are unaffected ──
-- 7. An out-of-zone ping (~1.1 km east) lands at full precision and is
--    NOT flagged coarse. It coexists with the coarse last-seen.
insert into race_pings (event_id, instance_start, user_id, at, lat, lng)
values (
  '55555555-5555-5555-5555-555555555502',
  '2026-07-04 10:00:00+00',
  '00000000-0000-0000-0000-0000000006c1',
  now(), 47.37, 8.5550
);

select is(
  (select count(*)::int from race_pings
     where user_id = '00000000-0000-0000-0000-0000000006c1'
       and coarse = false),
  1,
  'out-of-zone race ping is stored at full precision, not flagged coarse'
);

-- 8. That out-of-zone ping keeps its exact lng (no coarsening applied).
select is(
  (select lng from race_pings
     where user_id = '00000000-0000-0000-0000-0000000006c1'
       and coarse = false),
  8.5550::double precision,
  'out-of-zone race ping retains full-precision coordinates'
);

-- 9. Exactly one coarse last-seen coexists with the precise out-of-zone
--    ping — the leaderboard shows the runner's current precise position
--    AND does not lose the earlier in-zone stop.
select is(
  (select count(*)::int from race_pings
     where user_id = '00000000-0000-0000-0000-0000000006c1'
       and coarse = true),
  1,
  'coarse last-seen coexists with the out-of-zone precise ping'
);

select * from finish();

rollback;
