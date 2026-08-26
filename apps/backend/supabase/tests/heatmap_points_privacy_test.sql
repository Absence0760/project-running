-- pgtap suite for the privacy-zone clip inside `heatmap_points_in_bbox`
-- (migration 20270504_001).
--
-- The RPC is SECURITY DEFINER and granted to `anon`, and it densifies the
-- whole route polyline at ~50 m. Before the fix it emitted every densified
-- point, including the stretch inside the owner's privacy zone, so an
-- anonymous caller could recover the walk from the clip boundary to the front
-- door by posting a bbox that touches a public route near its owner's home.
--
-- Note the RPC selects ROUTES by bbox but returns their points in full — the
-- bbox is not a clip on the output — so "query a tight box" is not the assertion
-- to make. What matters is which points come back at all.
--
-- Everything runs as `anon`: the leak was reachable with no session at all.

begin;

select plan(5);

-- ── Fixture ──────────────────────────────────────────────────────────
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000e101', 'authenticated', 'authenticated',
   'zoned@heatmap.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000e102', 'authenticated', 'authenticated',
   'open@heatmap.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000e103', 'authenticated', 'authenticated',
   'homebound@heatmap.local', '', now(), now());

-- Zone on (47.37, 8.54), 150 m radius. At this latitude 0.001° of longitude is
-- ~75 m and 0.001° of latitude ~111 m, so the ±0.001° box asserted on below
-- sits wholly inside the circle (corner ≈ 134 m).
insert into user_settings (user_id, prefs)
values (
  '00000000-0000-0000-0000-00000000e101',
  jsonb_build_object(
    'privacy_zones', jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.54, 'radius_m', 150)
    )
  )
),
(
  '00000000-0000-0000-0000-00000000e103',
  jsonb_build_object(
    'privacy_zones', jsonb_build_array(
      jsonb_build_object('lat', 47.10, 'lng', 8.54, 'radius_m', 400)
    )
  )
);

-- A public route that starts at the zoned owner's home and runs ~1.5 km east.
insert into routes (id, user_id, name, distance_m, waypoints, is_public)
values (
  '00000000-0000-0000-0000-00000000e201',
  '00000000-0000-0000-0000-00000000e101',
  'zoned owner — starts at home',
  1500,
  '[{"lat":47.37,"lng":8.54},{"lat":47.37,"lng":8.55},{"lat":47.37,"lng":8.56}]'::jsonb,
  true
),
-- Owner e102 has no user_settings row at all.
(
  '00000000-0000-0000-0000-00000000e202',
  '00000000-0000-0000-0000-00000000e102',
  'unzoned owner',
  1500,
  '[{"lat":47.30,"lng":8.54},{"lat":47.30,"lng":8.55}]'::jsonb,
  true
),
-- A public route that never leaves its owner's 400 m zone.
(
  '00000000-0000-0000-0000-00000000e203',
  '00000000-0000-0000-0000-00000000e103',
  'laps around the block',
  400,
  '[{"lat":47.1000,"lng":8.5400},{"lat":47.1005,"lng":8.5405},{"lat":47.1000,"lng":8.5410}]'::jsonb,
  true
),
-- A private route, to confirm the is_public gate still holds.
(
  '00000000-0000-0000-0000-00000000e204',
  '00000000-0000-0000-0000-00000000e102',
  'private',
  1500,
  '[{"lat":47.20,"lng":8.54},{"lat":47.20,"lng":8.55}]'::jsonb,
  false
);

set local role anon;
select set_config('request.jwt.claims', null, true);

-- 1. The layer still works: the out-of-zone stretch is returned.
select cmp_ok(
  (select count(*) from heatmap_points_in_bbox(8.53, 47.36, 8.57, 47.38, 5000))::int,
  '>', 0::int,
  'heatmap still returns the out-of-zone stretch of a public route'
);

-- 2. The leak itself. The densified walk used to start ~50 m from the first
--    waypoint, i.e. inside the owner's zone.
-- refusal: the privacy-zone clip is the whole privacy contract of the heatmap
select is(
  (select count(*)
     from heatmap_points_in_bbox(8.53, 47.36, 8.57, 47.38, 5000) p
    where abs(p.lat - 47.37) < 0.001
      and abs(p.lng - 8.54) < 0.001)::int,
  0::int,
  'no heatmap point lands inside the route owner''s privacy zone'
);

-- 3. A public route that never leaves its owner's zone contributes nothing.
-- refusal: the privacy-zone clip is the whole privacy contract of the heatmap
select is(
  (select count(*) from heatmap_points_in_bbox(8.53, 47.09, 8.55, 47.11, 5000))::int,
  0::int,
  'a route entirely inside a privacy zone yields no points'
);

-- 4. A missing user_settings row must not blank the layer — the left join
--    leaves `zones` NULL and every point is kept.
select cmp_ok(
  (select count(*) from heatmap_points_in_bbox(8.53, 47.29, 8.56, 47.31, 5000))::int,
  '>', 0::int,
  'a route whose owner has no user_settings row is still rendered'
);

-- 5. The is_public gate is unchanged.
-- refusal: an unpublished route must not be inferable from an aggregate
select is(
  (select count(*) from heatmap_points_in_bbox(8.53, 47.19, 8.56, 47.21, 5000))::int,
  0::int,
  'a private route contributes no heatmap points'
);

select * from finish();
rollback;
