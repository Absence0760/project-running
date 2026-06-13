-- pgtap suite for the privacy-vs-safety carve-out on live_run_pings
-- (migration 20270121_001).
--
-- Background: 20260618_001 drops any in-zone ping outright, so a runner
-- who stops inside their own privacy zone vanishes from the spectator +
-- SAR feed. The carve-out keeps the SINGLE most-recent in-zone ping per
-- run, coarsened to a ~2-dp grid (~1 km) and flagged coarse=true; older
-- in-zone coarse pings are replaced, not accumulated; out-of-zone pings
-- are untouched.
--
-- A regression here is a privacy/safety failure in BOTH directions: a
-- precise in-zone point reaching the feed leaks the home address; a
-- dropped last-seen makes an injured runner invisible to a search.

begin;

select plan(11);

-- ── Fixture: one runner with a privacy zone, one public run ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000005a1', 'authenticated', 'authenticated',
   'sar@carveout.local', '', now(), now());

-- Zone: ~150 m radius around (47.37, 8.54).
insert into user_settings (user_id, prefs)
values (
  '00000000-0000-0000-0000-0000000005a1',
  jsonb_build_object(
    'privacy_zones', jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.54, 'radius_m', 150)
    )
  )
);

insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, metadata)
values (
  '00000000-0000-0000-0000-0000000005b1',
  '00000000-0000-0000-0000-0000000005a1',
  now(), 1000, 600, 'app', true, '{"activity_type":"run"}'
);

set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"00000000-0000-0000-0000-0000000005a1","role":"authenticated"}';

-- ── privacy_coarsen_coord (helper internals) ──
reset role;

-- 1. Coarsens to 2 decimal places.
select is(
  privacy_coarsen_coord(47.376123),
  47.38::double precision,
  'privacy_coarsen_coord rounds to 2 decimal places'
);

-- 2. The coarsened zone-centre is NOT the exact centre (no exact leak).
select isnt(
  privacy_coarsen_coord(8.54199),
  8.54199::double precision,
  'privacy_coarsen_coord drops sub-2-dp precision'
);

set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"00000000-0000-0000-0000-0000000005a1","role":"authenticated"}';

-- ── In-zone ping is stored coarsened, never precise ──
-- 3. A precise in-zone ping (the exact zone centre) lands as exactly one
--    coarse row — it is NOT dropped (the old behaviour) and NOT stored
--    at full precision.
insert into live_run_pings (run_id, user_id, lat, lng, ele)
values (
  '00000000-0000-0000-0000-0000000005b1',
  '00000000-0000-0000-0000-0000000005a1',
  47.370001, 8.540001, 312.5
);

select is(
  (select count(*)::int from live_run_pings
     where run_id = '00000000-0000-0000-0000-0000000005b1'),
  1,
  'in-zone ping is retained (not dropped) as a coarse last-seen'
);

-- 4. The stored ping is flagged coarse.
select is(
  (select coarse from live_run_pings
     where run_id = '00000000-0000-0000-0000-0000000005b1'),
  true,
  'retained in-zone ping is flagged coarse = true'
);

-- 5. The stored lat/lng are coarsened to the 2-dp grid, not the precise
--    input — the exact home point never reaches the feed.
select is(
  (select lat from live_run_pings
     where run_id = '00000000-0000-0000-0000-0000000005b1'),
  47.37::double precision,
  'retained in-zone ping lat is coarsened to 2 dp'
);
select is(
  (select lng from live_run_pings
     where run_id = '00000000-0000-0000-0000-0000000005b1'),
  8.54::double precision,
  'retained in-zone ping lng is coarsened to 2 dp'
);

-- 6. Elevation is stripped from the coarse last-seen (it would otherwise
--    carry exact altitude alongside the coarsened position).
select is(
  (select ele from live_run_pings
     where run_id = '00000000-0000-0000-0000-0000000005b1'),
  null,
  'retained in-zone ping has elevation stripped'
);

-- ── A second in-zone ping REPLACES the coarse last-seen ──
-- 7. Inserting another in-zone ping (a slightly different spot in the
--    zone) leaves still exactly one coarse row — it replaces, not
--    accumulates.
insert into live_run_pings (run_id, user_id, lat, lng)
values (
  '00000000-0000-0000-0000-0000000005b1',
  '00000000-0000-0000-0000-0000000005a1',
  47.370900, 8.539200
);

select is(
  (select count(*)::int from live_run_pings
     where run_id = '00000000-0000-0000-0000-0000000005b1'),
  1,
  'a second in-zone ping replaces the coarse last-seen (no accumulation)'
);

-- 8. The surviving row is the NEWER one, still coarsened.
select is(
  (select lng from live_run_pings
     where run_id = '00000000-0000-0000-0000-0000000005b1'),
  8.54::double precision,
  'the replacing coarse last-seen is itself coarsened to 2 dp'
);

-- ── Out-of-zone pings are unaffected ──
-- 9. An out-of-zone ping (~1.1 km east) lands at full precision and is
--    NOT flagged coarse. It coexists with the coarse last-seen.
insert into live_run_pings (run_id, user_id, lat, lng)
values (
  '00000000-0000-0000-0000-0000000005b1',
  '00000000-0000-0000-0000-0000000005a1',
  47.37, 8.5550
);

select is(
  (select count(*)::int from live_run_pings
     where run_id = '00000000-0000-0000-0000-0000000005b1'
       and coarse = false),
  1,
  'out-of-zone ping is stored at full precision, not flagged coarse'
);

-- 10. That out-of-zone ping keeps its exact lng (no coarsening applied).
select is(
  (select lng from live_run_pings
     where run_id = '00000000-0000-0000-0000-0000000005b1'
       and coarse = false),
  8.5550::double precision,
  'out-of-zone ping retains full-precision coordinates'
);

select * from finish();

rollback;
