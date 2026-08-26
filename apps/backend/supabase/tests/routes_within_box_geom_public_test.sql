-- pgtap suite for the privacy-aware `routes.geom_public` column
-- (migration 20270509_001 — closes the `routes_within_box` membership
-- oracle over the unclipped `geom`).
--
-- The defect: `routes_within_box` is granted to `anon` and its response
-- is redacted, but its predicate ran against the RAW polyline while
-- carrying the route id. A grid sweep of small boxes therefore traced
-- the in-zone tail of a public route at box resolution — geometry the
-- read path (`clip_route_for_viewer`) deliberately withholds.
--
-- The fix repoints the predicate at `geom_public`, the LineString of
-- exactly the waypoints a non-owner is already served. The assertions
-- below are the oracle itself: a box drawn over the in-zone head must
-- return nothing even though the raw `geom` crosses it, while a box over
-- the out-of-zone body still returns the route.

begin;

select plan(10);

-- ── Fixture: one user with a zone, one without ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000e201', 'authenticated', 'authenticated',
   'a@geompublic.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000e202', 'authenticated', 'authenticated',
   'b@geompublic.local', '', now(), now());

-- User A has a zone around (47.37, 8.54) with a 150 m radius. At this
-- latitude 0.0001 degrees of longitude is roughly 7.5 m, so 8.5405 sits
-- ~38 m east (inside the zone) and 8.5500 sits ~750 m east (outside it).
insert into user_settings (user_id, prefs)
values (
  '00000000-0000-0000-0000-00000000e201',
  jsonb_build_object(
    'privacy_zones', jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.54, 'radius_m', 150)
    )
  )
);

-- A: starts inside the zone, runs east out of it.
insert into routes (id, user_id, name, distance_m, waypoints, is_public)
values (
  '00000000-0000-0000-0000-00000000e301',
  '00000000-0000-0000-0000-00000000e201',
  'A route — head in zone',
  1500,
  '[{"lat":47.37,"lng":8.5400},{"lat":47.37,"lng":8.5405},'
  '{"lat":47.37,"lng":8.5500},{"lat":47.37,"lng":8.5600}]'::jsonb,
  true
);

-- C: entirely inside the zone.
insert into routes (id, user_id, name, distance_m, waypoints, is_public)
values (
  '00000000-0000-0000-0000-00000000e303',
  '00000000-0000-0000-0000-00000000e201',
  'A route — entirely in zone',
  100,
  '[{"lat":47.37,"lng":8.5400},{"lat":47.3701,"lng":8.5401},'
  '{"lat":47.3702,"lng":8.5402}]'::jsonb,
  true
);

-- B: same shape as A but the owner has no zones yet.
insert into routes (id, user_id, name, distance_m, waypoints, is_public)
values (
  '00000000-0000-0000-0000-00000000e302',
  '00000000-0000-0000-0000-00000000e202',
  'B route — no zones',
  1500,
  '[{"lat":47.37,"lng":8.5400},{"lat":47.37,"lng":8.5500},'
  '{"lat":47.37,"lng":8.5600}]'::jsonb,
  true
);

-- ─────────────────────────────────────────────────────────────────────
-- The column itself
-- ─────────────────────────────────────────────────────────────────────

select isnt(
  (select geom_public from routes where id = '00000000-0000-0000-0000-00000000e301'),
  null,
  'A route with an out-of-zone body gets a geom_public line'
);

select is(
  (select ST_Equals(geom::geometry, geom_public::geometry)
     from routes where id = '00000000-0000-0000-0000-00000000e301'),
  false,
  'geom_public is NOT the raw geom — the in-zone head was clipped off'
);

select is(
  (select geom_public from routes where id = '00000000-0000-0000-0000-00000000e303'),
  null,
  'a fully-in-zone route has a NULL geom_public'
);

-- ─────────────────────────────────────────────────────────────────────
-- The oracle. The head box covers only the stretch inside A''s zone.
-- ─────────────────────────────────────────────────────────────────────

-- The raw polyline DOES cross the head box — without this the "not
-- returned" assertion below would pass for the wrong reason.
select is(
  (select ST_Intersects(
            r.geom,
            ST_SetSRID(ST_MakeEnvelope(8.5395, 47.3695, 8.5410, 47.3705), 4326)::geography
          )
     from routes r where r.id = '00000000-0000-0000-0000-00000000e301'),
  true,
  'the raw geom does cross the head box (the old predicate would have matched)'
);

set local role anon;

-- refusal: geom_public is the privacy-clipped geometry, and matching on the raw line would reopen the oracle
select is(
  (select count(*)
     from routes_within_box(47.3695, 8.5395, 47.3705, 8.5410, 50)
    where id = '00000000-0000-0000-0000-00000000e301')::int,
  0::int,
  'anon: a box over the in-zone head does NOT return the route (oracle closed)'
);

-- refusal: a null clipped geometry must fail closed rather than fall back to the raw line
select is(
  (select count(*)
     from routes_within_box(47.3695, 8.5395, 47.3705, 8.5410, 50)
    where id = '00000000-0000-0000-0000-00000000e303')::int,
  0::int,
  'anon: a fully-in-zone route is never returned (fail-closed on NULL geom_public)'
);

select is(
  (select count(*)
     from routes_within_box(47.3695, 8.5550, 47.3705, 8.5580, 50)
    where id = '00000000-0000-0000-0000-00000000e301')::int,
  1::int,
  'anon: a box over the out-of-zone body still returns the route'
);

-- B has no zones, so its public line is the whole polyline and the head
-- box still finds it.
select is(
  (select count(*)
     from routes_within_box(47.3695, 8.5395, 47.3705, 8.5410, 50)
    where id = '00000000-0000-0000-0000-00000000e302')::int,
  1::int,
  'anon: a no-zones route is unaffected — the head box returns it'
);

reset role;

-- ─────────────────────────────────────────────────────────────────────
-- user_settings trigger — adding a zone re-clips geom_public across
-- every route the user owns, not just the ones saved afterwards.
-- ─────────────────────────────────────────────────────────────────────

update user_settings
  set prefs = jsonb_build_object(
    'privacy_zones', jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.54, 'radius_m', 150)
    )
  )
  where user_id = '00000000-0000-0000-0000-00000000e202';

-- B had no user_settings row, so the UPDATE above was a no-op. Insert
-- the row, then fire the AFTER UPDATE trigger with a real zones change.
insert into user_settings (user_id, prefs)
values (
  '00000000-0000-0000-0000-00000000e202',
  jsonb_build_object('privacy_zones', '[]'::jsonb)
);

update user_settings
  set prefs = jsonb_build_object(
    'privacy_zones', jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.54, 'radius_m', 150)
    )
  )
  where user_id = '00000000-0000-0000-0000-00000000e202';

set local role anon;

-- refusal: a zone added later has to take effect on reads already possible before it
select is(
  (select count(*)
     from routes_within_box(47.3695, 8.5395, 47.3705, 8.5410, 50)
    where id = '00000000-0000-0000-0000-00000000e302')::int,
  0::int,
  'adding a zone retroactively drops the route from a head-box sweep'
);

select is(
  (select count(*)
     from routes_within_box(47.3695, 8.5550, 47.3705, 8.5580, 50)
    where id = '00000000-0000-0000-0000-00000000e302')::int,
  1::int,
  'the re-clipped route is still discoverable by its out-of-zone body'
);

reset role;

select * from finish();
rollback;
