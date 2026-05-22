-- Seed script for local development
-- Populates tables with realistic mock data for a test user.
--
-- Usage:
--   1. supabase db reset         (runs migrations + this seed)
--   2. Sign up at http://localhost:7777/login with any email/password
--   3. Run the SQL below in Supabase Studio (SQL Editor) to assign data
--      to your user, OR use the pre-created user:
--
-- Pre-created test user:
--   Email:    runner@test.com
--   Password: testtest
--
-- The user is created via pgcrypto (enabled below).

-- Enable pgcrypto for password hashing
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- 1. Create test user in auth.users
INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change_token_current,
  email_change, phone, phone_change, phone_change_token, reauthentication_token,
  is_sso_user, is_anonymous,
  raw_app_meta_data, raw_user_meta_data
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'authenticated', 'authenticated',
  'runner@test.com',
  extensions.crypt('testtest', extensions.gen_salt('bf')),
  now(), now(), now(),
  '', '', '', '',
  '', '', '', '', '',
  false, false,
  '{"provider":"email","providers":["email"]}',
  '{"email_verified":true}'
) ON CONFLICT (id) DO NOTHING;

-- auth.identities row (required by Supabase auth)
INSERT INTO auth.identities (
  id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
) VALUES (
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  jsonb_build_object('sub', 'a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'email', 'runner@test.com', 'email_verified', true),
  'email', now(), now(), now()
) ON CONFLICT DO NOTHING;

-- 2. User profile
INSERT INTO user_profiles (id, display_name, parkrun_number, preferred_unit, subscription_tier)
VALUES ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Jared Howard', 'A123456', 'km', 'free')
ON CONFLICT (id) DO NOTHING;

-- 2a. User settings — runner_context for the AI Coach. Without these the
-- coach has nothing to ground HR / age / weekly-goal answers in. Keys
-- match `docs/settings.md` § Universal prefs registry.
INSERT INTO user_settings (user_id, prefs) VALUES (
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  jsonb_build_object(
    'date_of_birth', '1992-09-12',
    'resting_hr_bpm', 48,
    'max_hr_bpm', 192,
    'hr_zones', jsonb_build_object('z1', 134, 'z2', 154, 'z3', 173, 'z4', 183, 'z5', 192),
    'weekly_mileage_goal_m', 50000,
    'coach_personality', 'supportive',
    'auto_pause_enabled', true,
    'preferred_unit', 'km',
    'week_start_day', 'monday'
  )
) ON CONFLICT (user_id) DO UPDATE SET prefs = EXCLUDED.prefs;

-- 3. Routes
-- Waypoints include `ele` (metres above sea level) so the route detail
-- page's elevation grid + interactive chart light up. Density is also
-- bumped above the original 2-4 sparse corner clicks so the rendered
-- polyline approximates the saved `distance_m` and the elevation
-- profile has enough samples to read like a real run.
INSERT INTO routes (user_id, name, waypoints, distance_m, elevation_m, surface, is_public) VALUES
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Richmond Park Loop',
  '[{"lat":-37.8136,"lng":144.9631,"ele":30},{"lat":-37.8128,"lng":144.9650,"ele":40},{"lat":-37.8120,"lng":144.9670,"ele":55},{"lat":-37.8112,"lng":144.9690,"ele":70},{"lat":-37.8104,"lng":144.9700,"ele":85},{"lat":-37.8096,"lng":144.9690,"ele":100},{"lat":-37.8088,"lng":144.9680,"ele":115},{"lat":-37.8080,"lng":144.9670,"ele":105},{"lat":-37.8072,"lng":144.9660,"ele":95},{"lat":-37.8060,"lng":144.9650,"ele":85},{"lat":-37.8056,"lng":144.9640,"ele":75},{"lat":-37.8064,"lng":144.9630,"ele":65},{"lat":-37.8076,"lng":144.9625,"ele":55},{"lat":-37.8088,"lng":144.9620,"ele":48},{"lat":-37.8100,"lng":144.9618,"ele":42},{"lat":-37.8112,"lng":144.9620,"ele":38},{"lat":-37.8120,"lng":144.9624,"ele":34},{"lat":-37.8128,"lng":144.9628,"ele":31},{"lat":-37.8136,"lng":144.9631,"ele":30}]',
  10200, 85, 'trail', true),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Thames Path 5K',
  '[{"lat":-37.8200,"lng":144.9500,"ele":18},{"lat":-37.8195,"lng":144.9510,"ele":19},{"lat":-37.8192,"lng":144.9525,"ele":21},{"lat":-37.8189,"lng":144.9540,"ele":22},{"lat":-37.8187,"lng":144.9555,"ele":24},{"lat":-37.8185,"lng":144.9568,"ele":26},{"lat":-37.8183,"lng":144.9580,"ele":28},{"lat":-37.8182,"lng":144.9588,"ele":30},{"lat":-37.8181,"lng":144.9594,"ele":30},{"lat":-37.8181,"lng":144.9598,"ele":28},{"lat":-37.8180,"lng":144.9600,"ele":26}]',
  5000, 12, 'road', false),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Battersea Park Out & Back',
  '[{"lat":-37.8150,"lng":144.9550,"ele":5},{"lat":-37.8140,"lng":144.9580,"ele":7},{"lat":-37.8132,"lng":144.9610,"ele":11},{"lat":-37.8120,"lng":144.9645,"ele":16},{"lat":-37.8108,"lng":144.9675,"ele":20},{"lat":-37.8100,"lng":144.9700,"ele":25},{"lat":-37.8108,"lng":144.9675,"ele":23},{"lat":-37.8120,"lng":144.9645,"ele":19},{"lat":-37.8132,"lng":144.9610,"ele":15},{"lat":-37.8140,"lng":144.9580,"ele":12},{"lat":-37.8146,"lng":144.9565,"ele":9},{"lat":-37.8150,"lng":144.9550,"ele":5}]',
  7800, 20, 'road', true),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Sunday Long Run',
  '[{"lat":-37.8136,"lng":144.9631,"ele":50},{"lat":-37.8100,"lng":144.9670,"ele":62},{"lat":-37.8060,"lng":144.9710,"ele":78},{"lat":-37.8020,"lng":144.9750,"ele":98},{"lat":-37.7980,"lng":144.9780,"ele":118},{"lat":-37.7920,"lng":144.9800,"ele":135},{"lat":-37.7900,"lng":144.9800,"ele":120},{"lat":-37.7920,"lng":144.9850,"ele":105},{"lat":-37.7950,"lng":144.9900,"ele":95},{"lat":-37.7980,"lng":144.9940,"ele":105},{"lat":-37.8000,"lng":145.0000,"ele":120},{"lat":-37.8030,"lng":144.9980,"ele":140},{"lat":-37.8050,"lng":144.9950,"ele":160},{"lat":-37.8060,"lng":144.9920,"ele":180},{"lat":-37.8075,"lng":144.9890,"ele":160},{"lat":-37.8090,"lng":144.9850,"ele":135},{"lat":-37.8100,"lng":144.9810,"ele":110},{"lat":-37.8110,"lng":144.9770,"ele":92},{"lat":-37.8118,"lng":144.9730,"ele":78},{"lat":-37.8124,"lng":144.9690,"ele":68},{"lat":-37.8128,"lng":144.9665,"ele":60},{"lat":-37.8132,"lng":144.9650,"ele":55},{"lat":-37.8134,"lng":144.9640,"ele":52},{"lat":-37.8136,"lng":144.9631,"ele":50}]',
  21100, 140, 'mixed', false),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Commute Run',
  '[{"lat":-37.8180,"lng":144.9550,"ele":10},{"lat":-37.8170,"lng":144.9575,"ele":14},{"lat":-37.8160,"lng":144.9600,"ele":20},{"lat":-37.8150,"lng":144.9620,"ele":27},{"lat":-37.8140,"lng":144.9640,"ele":35},{"lat":-37.8130,"lng":144.9655,"ele":40},{"lat":-37.8125,"lng":144.9665,"ele":38},{"lat":-37.8118,"lng":144.9675,"ele":42},{"lat":-37.8112,"lng":144.9685,"ele":45},{"lat":-37.8108,"lng":144.9692,"ele":42},{"lat":-37.8105,"lng":144.9697,"ele":40},{"lat":-37.8100,"lng":144.9700,"ele":38}]',
  6400, 35, 'road', false);

-- Virginia routes for the local Protomaps tile-extract dev setup
-- (`bin/protomaps-dev.sh` defaults to Virginia, decisions.md § 68).
-- All routes are `is_public = true` so they also surface in the
-- heatmap RPC + Explore tab. Coordinates are hand-picked from real
-- Virginia running landmarks so the map looks recognisable when the
-- operator boots the local stack + opens the route detail page.
INSERT INTO routes (user_id, name, waypoints, distance_m, elevation_m, surface, is_public) VALUES
-- Richmond's signature urban-park loop — Belle Isle bridge to the
-- Floodwall + back along the Pipeline Walk + Lehigh Trail.
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Belle Isle + Pipeline Loop (Richmond)',
  '[{"lat":37.5311,"lng":-77.4520,"ele":58},{"lat":37.5318,"lng":-77.4500,"ele":54},{"lat":37.5325,"lng":-77.4480,"ele":50},{"lat":37.5331,"lng":-77.4460,"ele":47},{"lat":37.5335,"lng":-77.4438,"ele":45},{"lat":37.5340,"lng":-77.4418,"ele":43},{"lat":37.5346,"lng":-77.4398,"ele":41},{"lat":37.5352,"lng":-77.4378,"ele":40},{"lat":37.5358,"lng":-77.4360,"ele":42},{"lat":37.5362,"lng":-77.4345,"ele":45},{"lat":37.5365,"lng":-77.4330,"ele":48},{"lat":37.5360,"lng":-77.4348,"ele":50},{"lat":37.5354,"lng":-77.4368,"ele":48},{"lat":37.5348,"lng":-77.4388,"ele":46},{"lat":37.5342,"lng":-77.4408,"ele":44},{"lat":37.5337,"lng":-77.4428,"ele":42},{"lat":37.5333,"lng":-77.4448,"ele":44},{"lat":37.5328,"lng":-77.4468,"ele":48},{"lat":37.5322,"lng":-77.4488,"ele":52},{"lat":37.5315,"lng":-77.4508,"ele":56},{"lat":37.5311,"lng":-77.4520,"ele":58}]',
  6500, 70, 'mixed', true),
-- UVA loop in Charlottesville: Rotunda → Madison Hall → Mad Bowl →
-- Beta Bridge → Corner → back. A real campus tempo run.
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'UVA Rotunda Loop (Charlottesville)',
  '[{"lat":38.0356,"lng":-78.5067,"ele":150},{"lat":38.0362,"lng":-78.5070,"ele":152},{"lat":38.0368,"lng":-78.5075,"ele":155},{"lat":38.0373,"lng":-78.5082,"ele":160},{"lat":38.0378,"lng":-78.5090,"ele":165},{"lat":38.0382,"lng":-78.5100,"ele":168},{"lat":38.0384,"lng":-78.5110,"ele":170},{"lat":38.0385,"lng":-78.5120,"ele":168},{"lat":38.0382,"lng":-78.5128,"ele":166},{"lat":38.0376,"lng":-78.5132,"ele":164},{"lat":38.0368,"lng":-78.5130,"ele":162},{"lat":38.0360,"lng":-78.5125,"ele":160},{"lat":38.0355,"lng":-78.5115,"ele":158},{"lat":38.0352,"lng":-78.5102,"ele":155},{"lat":38.0350,"lng":-78.5090,"ele":153},{"lat":38.0351,"lng":-78.5078,"ele":151},{"lat":38.0356,"lng":-78.5067,"ele":150}]',
  4200, 45, 'road', true),
-- Mount Vernon Trail (Arlington/Alexandria) — a classic out-and-back
-- north along the Potomac. ~10 km from Memorial Bridge to Belle Haven.
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Mount Vernon Trail North (Arlington)',
  '[{"lat":38.8870,"lng":-77.0560,"ele":10},{"lat":38.8845,"lng":-77.0540,"ele":11},{"lat":38.8810,"lng":-77.0518,"ele":12},{"lat":38.8770,"lng":-77.0498,"ele":13},{"lat":38.8730,"lng":-77.0480,"ele":14},{"lat":38.8690,"lng":-77.0468,"ele":15},{"lat":38.8645,"lng":-77.0455,"ele":16},{"lat":38.8595,"lng":-77.0445,"ele":17},{"lat":38.8540,"lng":-77.0438,"ele":18},{"lat":38.8485,"lng":-77.0432,"ele":18},{"lat":38.8430,"lng":-77.0428,"ele":19},{"lat":38.8485,"lng":-77.0432,"ele":18},{"lat":38.8540,"lng":-77.0438,"ele":18},{"lat":38.8595,"lng":-77.0445,"ele":17},{"lat":38.8645,"lng":-77.0455,"ele":16},{"lat":38.8690,"lng":-77.0468,"ele":15},{"lat":38.8730,"lng":-77.0480,"ele":14},{"lat":38.8770,"lng":-77.0498,"ele":13},{"lat":38.8810,"lng":-77.0518,"ele":12},{"lat":38.8845,"lng":-77.0540,"ele":11},{"lat":38.8870,"lng":-77.0560,"ele":10}]',
  10200, 25, 'trail', true),
-- Norfolk Botanical Garden — small but pretty 3-mile loop on
-- gravel + paved paths.
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Norfolk Botanical Garden Loop',
  '[{"lat":36.8983,"lng":-76.2030,"ele":3},{"lat":36.8990,"lng":-76.2015,"ele":4},{"lat":36.8998,"lng":-76.2000,"ele":5},{"lat":36.9005,"lng":-76.1985,"ele":6},{"lat":36.9008,"lng":-76.1968,"ele":7},{"lat":36.9006,"lng":-76.1952,"ele":7},{"lat":36.9000,"lng":-76.1942,"ele":7},{"lat":36.8990,"lng":-76.1948,"ele":6},{"lat":36.8980,"lng":-76.1960,"ele":5},{"lat":36.8972,"lng":-76.1978,"ele":4},{"lat":36.8970,"lng":-76.1998,"ele":3},{"lat":36.8975,"lng":-76.2015,"ele":3},{"lat":36.8983,"lng":-76.2030,"ele":3}]',
  4800, 20, 'mixed', true),
-- Virginia Beach Boardwalk — pancake-flat out-and-back along the
-- ocean from 1st St up to ~38th.
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'VA Beach Boardwalk Out & Back',
  '[{"lat":36.8385,"lng":-75.9772,"ele":3},{"lat":36.8420,"lng":-75.9770,"ele":3},{"lat":36.8460,"lng":-75.9768,"ele":3},{"lat":36.8500,"lng":-75.9766,"ele":3},{"lat":36.8540,"lng":-75.9764,"ele":3},{"lat":36.8580,"lng":-75.9762,"ele":3},{"lat":36.8620,"lng":-75.9760,"ele":3},{"lat":36.8660,"lng":-75.9758,"ele":3},{"lat":36.8620,"lng":-75.9760,"ele":3},{"lat":36.8580,"lng":-75.9762,"ele":3},{"lat":36.8540,"lng":-75.9764,"ele":3},{"lat":36.8500,"lng":-75.9766,"ele":3},{"lat":36.8460,"lng":-75.9768,"ele":3},{"lat":36.8420,"lng":-75.9770,"ele":3},{"lat":36.8385,"lng":-75.9772,"ele":3}]',
  6300, 5, 'road', true),
-- Roanoke Mill Mountain Greenway — climbs Mill Mountain to the
-- star, then back down. The Virginia "hill-rep classic".
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Mill Mountain Star Climb (Roanoke)',
  '[{"lat":37.2710,"lng":-79.9416,"ele":280},{"lat":37.2700,"lng":-79.9400,"ele":300},{"lat":37.2688,"lng":-79.9385,"ele":330},{"lat":37.2675,"lng":-79.9370,"ele":365},{"lat":37.2660,"lng":-79.9355,"ele":405},{"lat":37.2645,"lng":-79.9345,"ele":445},{"lat":37.2630,"lng":-79.9338,"ele":485},{"lat":37.2615,"lng":-79.9335,"ele":520},{"lat":37.2602,"lng":-79.9332,"ele":555},{"lat":37.2592,"lng":-79.9330,"ele":580},{"lat":37.2602,"lng":-79.9332,"ele":555},{"lat":37.2615,"lng":-79.9335,"ele":520},{"lat":37.2630,"lng":-79.9338,"ele":485},{"lat":37.2645,"lng":-79.9345,"ele":445},{"lat":37.2660,"lng":-79.9355,"ele":405},{"lat":37.2675,"lng":-79.9370,"ele":365},{"lat":37.2688,"lng":-79.9385,"ele":330},{"lat":37.2700,"lng":-79.9400,"ele":300},{"lat":37.2710,"lng":-79.9416,"ele":280}]',
  7200, 300, 'trail', true);

-- Four Virginia run rows with explicit IDs that match the upload
-- targets in scripts/seed-run-tracks.mjs. The track itself doesn't
-- ship in this seed file — the tracks are gzipped JSON in Storage,
-- not jsonb columns, so seed.sql can't seed the bytes. Run
-- `npm run dev:db:seed-tracks` AFTER `supabase db reset` to upload
-- the matching files. Until then these runs show "No GPS track for
-- this run" on /runs/[id]; with the tracks uploaded they render
-- real polylines on the map.
INSERT INTO runs (id, user_id, started_at, duration_s, distance_m, source, is_public, track_url, metadata) VALUES
  -- Belle Isle + Pipeline Loop tempo run, Richmond
  ('a1000001-0000-0000-0000-000000000001'::uuid,
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    '2026-05-15 07:30:00+00', 2280, 6500.0, 'app', true,
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890/a1000001-0000-0000-0000-000000000001.json.gz',
    '{"activity_type":"run","title":"Tempo on Belle Isle","avg_bpm":158,"steps":7900}'::jsonb),
  -- UVA Rotunda Loop easy run, Charlottesville
  ('a1000001-0000-0000-0000-000000000002'::uuid,
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    '2026-05-12 18:00:00+00', 1620, 4200.0, 'app', true,
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890/a1000001-0000-0000-0000-000000000002.json.gz',
    '{"activity_type":"run","title":"UVA loop after work","avg_bpm":146,"steps":5400}'::jsonb),
  -- Mount Vernon Trail long run, Arlington
  ('a1000001-0000-0000-0000-000000000003'::uuid,
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    '2026-05-10 06:45:00+00', 3720, 10200.0, 'app', false,
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890/a1000001-0000-0000-0000-000000000003.json.gz',
    '{"activity_type":"run","title":"Sunday long along the Potomac","avg_bpm":152,"steps":12800}'::jsonb),
  -- Mill Mountain Star Climb hill workout, Roanoke
  ('a1000001-0000-0000-0000-000000000004'::uuid,
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    '2026-05-08 08:00:00+00', 2580, 7200.0, 'app', true,
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890/a1000001-0000-0000-0000-000000000004.json.gz',
    '{"activity_type":"run","title":"Star climb hill reps","avg_bpm":165,"steps":8800}'::jsonb);

-- Star three of the seeded routes so the watch picker shows a
-- realistic "what I run weekly" rotation out of the box. Without
-- this, the watch's starred-only fetch returns empty and a fresh
-- dev install looks broken until the user manually stars something.
-- Pick Virginia routes alongside the existing London ones so the
-- watch shows both regions — but the Belle Isle loop is the
-- "default" if the operator is testing the Protomaps tile extract.
UPDATE routes
SET is_starred = true
WHERE user_id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
  AND name IN (
    'Richmond Park Loop',
    'Thames Path 5K',
    'Sunday Long Run',
    'Belle Isle + Pipeline Loop (Richmond)',
    'UVA Rotunda Loop (Charlottesville)',
    'Mount Vernon Trail North (Arlington)'
  );

-- 3b. Gear. Two pairs of shoes — one current (default), one rotation.
-- Inserted BEFORE the runs table so the auto-tag trigger
-- (migration 20260901_001) stamps every shoe-eligible run with the
-- current default at insert time. The "default" flag is what makes
-- the gear chip appear on /runs/[id] without the user lifting a
-- finger; the second pair shows up as an option in the per-run gear
-- picker for runs where the user wore something different.
INSERT INTO gear (id, owner_id, kind, name, brand, model, purchased_at, target_distance_m, is_default) VALUES
  ('11111111-aaaa-bbbb-cccc-222222222201',
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    'shoe', 'Pegasus 40', 'Nike', 'Pegasus 40', '2026-02-15', 800000, true),
  ('11111111-aaaa-bbbb-cccc-222222222202',
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    'shoe', 'Ghost 16', 'Brooks', 'Ghost 16', '2026-03-20', 700000, false);

-- 4. Runs (spanning ~6 weeks of realistic training, anchored on 2026-04-26
-- as "today"). Metadata carries activity_type + HR + perceived effort so
-- the coach has signal to talk about effort drift, zone splits, and easy /
-- hard days. The most recent week (Apr 19-25) is the live picture the
-- coach grounds "should I run today?" answers in.
INSERT INTO runs (user_id, started_at, duration_s, distance_m, source, metadata) VALUES
-- Last week — the picture the coach uses to answer "today / tomorrow"
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-04-25T07:00:00Z', 5640, 21100, 'app',
  '{"activity_type":"run","avg_bpm":162,"max_bpm":178,"perceived_effort":7,"notes":"Long run — Centennial loops. Felt strong through 18 km, last 3 km in zone 4."}'),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-04-23T17:30:00Z', 2880, 10000, 'app',
  '{"activity_type":"run","avg_bpm":174,"max_bpm":188,"perceived_effort":8,"notes":"Tempo: 6 km @ 4:35 sandwich between 2 km easy. Hit splits on the nose."}'),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-04-22T06:45:00Z', 2640, 8000, 'app',
  '{"activity_type":"run","avg_bpm":146,"max_bpm":158,"perceived_effort":4,"notes":"Easy. Legs heavy from Tuesday."}'),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-04-21T17:30:00Z', 3000, 12000, 'app',
  '{"activity_type":"run","avg_bpm":171,"max_bpm":189,"perceived_effort":8,"notes":"5×1000 @ 4:00 with 400 jog. Last rep dropped to 4:08."}'),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-04-19T07:00:00Z', 4920, 17000, 'app',
  '{"activity_type":"run","avg_bpm":154,"max_bpm":168,"perceived_effort":5,"notes":"Long run — Centennial out & back. Comfortable."}'),
-- Two weeks ago
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-04-18T07:30:00Z', 1620, 5120, 'app',
  '{"activity_type":"run","avg_bpm":150,"max_bpm":162,"perceived_effort":4}'),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-04-16T18:00:00Z', 2940, 10030, 'app',
  '{"activity_type":"run","avg_bpm":172,"max_bpm":186,"perceived_effort":7,"notes":"Threshold — tempo block hit pace target."}'),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-04-15T07:30:00Z', 2640, 8000, 'app',
  '{"activity_type":"run","avg_bpm":148,"max_bpm":160,"perceived_effort":4}'),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-04-14T17:30:00Z', 3060, 12000, 'app',
  '{"activity_type":"run","avg_bpm":174,"max_bpm":190,"perceived_effort":9,"notes":"VO2 intervals — 5×1000. Strong session."}'),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-04-12T07:00:00Z', 4980, 17000, 'app',
  '{"activity_type":"run","avg_bpm":152,"max_bpm":165,"perceived_effort":5}'),
-- A parkrun PB (5K @ 21:00 = 1260s) — drives the personal_records cache
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-04-11T08:00:00Z', 1260, 5000, 'parkrun',
  '{"activity_type":"run","event":"Centennial","position":12,"age_grade":"61.42%","avg_bpm":182,"max_bpm":194,"perceived_effort":10,"notes":"5K PB! Even splits 4:14 / 4:12 / 4:10 / 4:12 / 4:12."}'),
-- Three weeks back
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-04-05T07:30:00Z', 1620, 5120, 'app',
  '{"activity_type":"run","avg_bpm":151,"max_bpm":163,"perceived_effort":4}'),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-04-03T06:45:00Z', 2940, 10030, 'app',
  '{"activity_type":"run","avg_bpm":166,"max_bpm":178,"perceived_effort":6}'),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-04-01T18:00:00Z', 1320, 5000, 'parkrun',
  '{"activity_type":"run","event":"Richmond","position":18,"age_grade":"58.64%","avg_bpm":180,"max_bpm":192,"perceived_effort":10}'),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-03-30T07:00:00Z', 3780, 12500, 'strava',
  '{"activity_type":"run","avg_bpm":156,"max_bpm":169,"perceived_effort":5}'),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-03-28T17:30:00Z', 1680, 5200, 'app',
  '{"activity_type":"run","avg_bpm":150,"max_bpm":162,"perceived_effort":4}'),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-03-26T06:30:00Z', 5460, 21100, 'strava',
  '{"activity_type":"run","avg_bpm":160,"max_bpm":174,"perceived_effort":6,"notes":"Long run — felt fine, pace drifted late."}'),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-03-25T07:15:00Z', 1380, 5000, 'parkrun',
  '{"activity_type":"run","event":"Bushy Park","position":22,"age_grade":"57.08%","avg_bpm":181,"max_bpm":193,"perceived_effort":10}'),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-03-23T06:00:00Z', 2700, 8800, 'app',
  '{"activity_type":"run","avg_bpm":148,"max_bpm":160,"perceived_effort":4}'),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-03-21T07:00:00Z', 1860, 6100, 'healthkit',
  '{"activity_type":"run","avg_bpm":152,"max_bpm":166,"perceived_effort":5}'),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-03-19T18:15:00Z', 2400, 7600, 'app',
  '{"activity_type":"run","avg_bpm":158,"max_bpm":172,"perceived_effort":5}'),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-03-17T06:45:00Z', 3300, 10100, 'strava',
  '{"activity_type":"run","avg_bpm":162,"max_bpm":175,"perceived_effort":6}'),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-03-15T07:30:00Z', 1410, 5000, 'parkrun',
  '{"activity_type":"run","event":"Richmond","position":24,"age_grade":"56.14%","avg_bpm":179,"max_bpm":190,"perceived_effort":10}'),
-- A 10K PB (40:00 = 2400s) — race source is excluded from the PB
-- cache, so this seeds the "all-runs" view but not personal_records.
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-03-08T08:30:00Z', 2400, 10000, 'race',
  '{"activity_type":"run","event":"Sydney 10K","avg_bpm":180,"max_bpm":192,"perceived_effort":10,"notes":"10K PB. Even pace, last 2 km hurt."}'),
-- 5K time trial (21:00 = 1260s) under `app` source so the personal_records
-- cache picks it up — the parkrun 5K at 4/11 is excluded by the cache's
-- source filter but is the actual all-time best the user references.
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-04-04T07:00:00Z', 1260, 5000, 'app',
  '{"activity_type":"run","avg_bpm":182,"max_bpm":195,"perceived_effort":10,"notes":"5K solo time trial. 4:14 / 4:12 / 4:10 / 4:12 / 4:12 — 21:00 flat."}'),
-- A 10K tempo at 41:00 (2460s) so the cache 10K PB is competitive
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-03-22T07:00:00Z', 2460, 10000, 'app',
  '{"activity_type":"run","avg_bpm":175,"max_bpm":188,"perceived_effort":9,"notes":"10K time-trial effort. Strong."}'),
-- A walk + a hike to exercise the activity_type mix. Distances kept
-- outside the 5K / 10K / half PB buckets so they don't pollute the
-- personal_records cache (the trigger groups by distance, not type).
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-04-20T16:00:00Z', 3600, 4200, 'app',
  '{"activity_type":"walk","avg_bpm":110,"perceived_effort":2,"notes":"Recovery walk."}'),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-04-13T09:00:00Z', 9000, 11500, 'app',
  '{"activity_type":"hike","avg_bpm":128,"perceived_effort":4,"notes":"Bondi → Coogee coastal."}');

-- 4b. Bulk back-history for pagination testing.
--
-- The hand-curated runs above stop on 2026-03-08; everything older is
-- generated programmatically here so /runs "All time" mode (PAGE_SIZE
-- = 50 per page) needs multiple "Load more" clicks to walk the full
-- list, and the dashboard / training-load chart / personal-records
-- cache all have realistic depth to exercise.
--
-- Each row gets a deterministic but varied duration / distance /
-- source pulled from a modular shuffle of the iteration index, so
-- the list reads as plausible variety rather than a constant
-- treadmill block. Activity type is always 'run' to keep the
-- default activity filter populated.
INSERT INTO runs (user_id, started_at, duration_s, distance_m, source, metadata)
SELECT
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890'::uuid,
  ('2026-03-07T07:00:00Z'::timestamptz - (n * INTERVAL '1 day')),
  (1800 + (n * 137 % 3000))::integer,
  (5000 + (n * 211 % 12000))::numeric,
  CASE n % 5
    WHEN 0 THEN 'strava'
    WHEN 1 THEN 'app'
    WHEN 2 THEN 'app'
    WHEN 3 THEN 'healthkit'
    ELSE 'parkrun'
  END,
  jsonb_build_object(
    'activity_type', 'run',
    'avg_bpm', 145 + (n % 30),
    'perceived_effort', 4 + (n % 5)
  )
FROM generate_series(1, 130) AS n;

-- Extra recent runs spread across the last ~7 days so /feed cursor
-- pagination (20 entries per page within the 14-day window) needs
-- a "Load more" click when alex@test.com browses runner's activity.
INSERT INTO runs (user_id, started_at, duration_s, distance_m, source, metadata)
SELECT
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890'::uuid,
  ('2026-04-26T18:00:00Z'::timestamptz - (n * INTERVAL '11 hours')),
  (1500 + (n * 89 % 1800))::integer,
  (4500 + (n * 137 % 7000))::numeric,
  CASE n % 4
    WHEN 0 THEN 'app'
    WHEN 1 THEN 'strava'
    WHEN 2 THEN 'app'
    ELSE 'healthkit'
  END,
  jsonb_build_object(
    'activity_type', 'run',
    'avg_bpm', 150 + (n % 25),
    'perceived_effort', 4 + (n % 4)
  )
FROM generate_series(1, 15) AS n;

-- Mark runner's runs public so the social loop (kudos / comments /
-- feed visibility) has material to work against when alex@test.com
-- (the second seed user) browses the app. The runs.is_public column
-- defaults to false; without this update Alex sees an empty profile.
UPDATE runs SET is_public = true
  WHERE user_id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';

-- 5. Integrations
INSERT INTO integrations (user_id, provider, last_sync_at) VALUES
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'parkrun', '2026-04-01T10:00:00Z'),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'strava', '2026-03-30T08:00:00Z');

-- ─────────────────────── 6. Clubs + events ───────────────────────
-- Three clubs exercising the full visibility × join-policy matrix:
--   * Public, open-join      — "Sydney Run Club"
--   * Public, request-to-join — "Tempo Tuesday"
--   * Private, invite-only    — "Friends of Jared"
--
-- Runner owns all three so the full admin surface (new event, invite link,
-- pending-requests panel, post composer) is reachable out of the box.

INSERT INTO clubs (id, owner_id, name, slug, description, location_label, is_public, join_policy, invite_token)
VALUES
  ('c1111111-0000-0000-0000-000000000001',
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
   'Sydney Run Club',
   'sydney-run-club',
   'Weekly long runs from Centennial Park. All paces, all welcome.',
   'Sydney, AU',
   true, 'open', null),
  ('c2222222-0000-0000-0000-000000000002',
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
   'Tempo Tuesday',
   'tempo-tuesday',
   'Weekly threshold session. Request to join — we keep the group around 15 so intervals stay tidy.',
   'Sydney, AU',
   true, 'request', null),
  ('c3333333-0000-0000-0000-000000000003',
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
   'Friends of Jared',
   'friends-of-jared',
   'Small private group for pre-race meetups and trip planning.',
   'Sydney, AU',
   false, 'invite',
   'c3fr13nd50fj4r3dc1ubtoken000000');

-- Rename + relocate the two public clubs from "Sydney" to Virginia
-- so the heatmap-tab discoverable-pin layer (clubs_in_bbox +
-- discoverable_routes_in_bbox, migration 20260911_001) reads
-- consistently with the Virginia route seeds + the Protomaps
-- Virginia tile extract. In a real-world flow the club editor
-- would set name + location_label + location_point together.
UPDATE clubs
   SET name = 'Richmond Run Club',
       description = 'Weekly long runs from Belle Isle. All paces, all welcome.',
       location_label = 'Richmond, VA',
       location_point = ST_GeogFromText('SRID=4326;POINT(-77.4360 37.5407)')
  WHERE id = 'c1111111-0000-0000-0000-000000000001'::uuid;
UPDATE clubs
   SET name = 'UVA Tempo Tuesday',
       description = 'Weekly threshold session in Charlottesville. Request to join — group around 15.',
       location_label = 'Charlottesville, VA',
       location_point = ST_GeogFromText('SRID=4326;POINT(-78.4767 38.0293)')
  WHERE id = 'c2222222-0000-0000-0000-000000000002'::uuid;

-- Six more public clubs across Virginia so the heatmap shows a
-- realistic spread + the "popular routes" + "clubs nearby" UX
-- has something to discover at city/region zoom. Each is owned
-- by the seed user (the `enroll_club_owner` trigger auto-inserts
-- the owner row in club_members; no manual member seed needed).
INSERT INTO clubs (id, owner_id, name, slug, description, location_label, location_point, is_public, join_policy, invite_token)
VALUES
  ('c4444444-0000-0000-0000-000000000004',
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
   'NoVA Trail Crew',
   'nova-trail-crew',
   'Weekend trail runs along the Mount Vernon Trail + W&OD. We meet at the Memorial Bridge.',
   'Arlington, VA',
   ST_GeogFromText('SRID=4326;POINT(-77.0560 38.8870)'),
   true, 'open', null),
  ('c5555555-0000-0000-0000-000000000005',
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
   'Norfolk Botanical Runners',
   'norfolk-botanical-runners',
   'Quiet morning loops through Norfolk Botanical Garden. Beginners + walk-run welcome.',
   'Norfolk, VA',
   ST_GeogFromText('SRID=4326;POINT(-76.2030 36.8983)'),
   true, 'open', null),
  ('c6666666-0000-0000-0000-000000000006',
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
   'VA Beach Boardwalk Striders',
   'va-beach-boardwalk-striders',
   'Sunrise runs on the Boardwalk year-round. 5K + 10K paces; weekend long runs in the summer.',
   'Virginia Beach, VA',
   ST_GeogFromText('SRID=4326;POINT(-75.9772 36.8385)'),
   true, 'open', null),
  ('c7777777-0000-0000-0000-000000000007',
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
   'Mill Mountain Hill Climbers',
   'mill-mountain-hill-climbers',
   'Tuesday hill repeats on the Mill Mountain Star greenway. If you like climbing, this is the group.',
   'Roanoke, VA',
   ST_GeogFromText('SRID=4326;POINT(-79.9416 37.2710)'),
   true, 'request', null),
  ('c8888888-0000-0000-0000-000000000008',
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
   'Richmond Marathon Trainers',
   'richmond-marathon-trainers',
   'Fall marathon training group out of Belle Isle. 16-week plan, Saturday long runs, Wednesday workouts.',
   'Richmond, VA',
   ST_GeogFromText('SRID=4326;POINT(-77.4500 37.5300)'),
   true, 'open', null),
  ('c9999999-0000-0000-0000-000000000009',
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
   'Blue Ridge Trail Society',
   'blue-ridge-trail-society',
   'Trail running, Skyline Drive day trips, Massanutten + Shenandoah event recon. Vans depart from UVA.',
   'Charlottesville, VA',
   ST_GeogFromText('SRID=4326;POINT(-78.5067 38.0356)'),
   true, 'request', null)
ON CONFLICT (id) DO NOTHING;

-- Flag three of the Virginia routes as `featured = true` so the
-- discoverable_routes_in_bbox RPC surfaces them at city-zoom on
-- the heatmap. Belle Isle + UVA + Mount Vernon are the three the
-- watch picker already stars by default — same visual shortlist.
UPDATE routes SET featured = true, featured_at = now()
  WHERE name IN (
    'Belle Isle + Pipeline Loop (Richmond)',
    'UVA Rotunda Loop (Charlottesville)',
    'Mount Vernon Trail North (Arlington)'
  );

-- Bump `run_count` on the three non-featured Virginia routes so
-- the "popular routes" path of discoverable_routes_in_bbox
-- (`featured = true OR run_count > 0`) lights up alongside the
-- featured ones. The trigger `routes_run_count_trigger` would
-- normally increment this when a run is matched to the route via
-- the run_match_pipeline; we set it directly in the seed to avoid
-- needing matched runs for the demo.
UPDATE routes SET run_count = 8 WHERE name = 'VA Beach Boardwalk Out & Back';
UPDATE routes SET run_count = 5 WHERE name = 'Norfolk Botanical Garden Loop';
UPDATE routes SET run_count = 3 WHERE name = 'Mill Mountain Star Climb (Roanoke)';

-- Post a mock pending request from a second auth user so the admin panel
-- has something to show. The user is created lightly (minimum columns) and
-- enrolled as `status='pending'` on the Tempo Tuesday club.
INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change_token_current,
  email_change, phone, phone_change, phone_change_token, reauthentication_token,
  is_sso_user, is_anonymous, raw_app_meta_data, raw_user_meta_data
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  'b2c3d4e5-f6a7-8901-bcde-f23456789012',
  'authenticated', 'authenticated',
  'alex@test.com',
  extensions.crypt('testtest', extensions.gen_salt('bf')),
  now(), now(), now(),
  '', '', '', '',
  '', NULL, '', '', '',
  false, false,
  '{"provider":"email","providers":["email"]}',
  '{"email_verified":true}'
) ON CONFLICT (id) DO NOTHING;

INSERT INTO auth.identities (
  id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
) VALUES (
  'b2c3d4e5-f6a7-8901-bcde-f23456789012',
  'b2c3d4e5-f6a7-8901-bcde-f23456789012',
  'b2c3d4e5-f6a7-8901-bcde-f23456789012',
  jsonb_build_object('sub', 'b2c3d4e5-f6a7-8901-bcde-f23456789012', 'email', 'alex@test.com', 'email_verified', true),
  'email', now(), now(), now()
) ON CONFLICT DO NOTHING;

INSERT INTO user_profiles (id, display_name, preferred_unit, subscription_tier)
VALUES ('b2c3d4e5-f6a7-8901-bcde-f23456789012', 'Alex Chen', 'km', 'free')
ON CONFLICT (id) DO NOTHING;

-- Alex joins Sydney Run Club as an active member + requests Tempo Tuesday.
-- (The owner row for each club is auto-inserted by the enroll_club_owner
-- trigger, so we only add Alex's rows here.)
INSERT INTO club_members (club_id, user_id, role, status) VALUES
  ('c1111111-0000-0000-0000-000000000001', 'b2c3d4e5-f6a7-8901-bcde-f23456789012', 'member', 'active'),
  ('c2222222-0000-0000-0000-000000000002', 'b2c3d4e5-f6a7-8901-bcde-f23456789012', 'member', 'pending')
ON CONFLICT DO NOTHING;

-- Events: two recurring weekly sessions + one one-off in the next 48h so
-- the Run-tab UpcomingEventCard is exercised.
INSERT INTO events (
  id, club_id, title, description, starts_at, duration_min, meet_label, distance_m, pace_target_sec,
  recurrence_freq, recurrence_byday, created_by
) VALUES
  ('e1111111-0000-0000-0000-000000000001',
   'c1111111-0000-0000-0000-000000000001',
   'Sunday Long Run',
   'Rolling start. We group up by pace at the gate — 4:30, 5:00, 5:30, 6:00. Coffee after.',
   '2026-04-19T06:30:00Z', 120, 'Centennial Park — Paddington Gate',
   18000, 330,
   'weekly', ARRAY['SU'],
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890'),
  ('e2222222-0000-0000-0000-000000000002',
   'c2222222-0000-0000-0000-000000000002',
   'Threshold Tuesday',
   '5×1 km @ threshold with 400m jog. Warmup + cooldown each 2 km.',
   '2026-04-14T17:30:00Z', 75, 'Centennial Park — Grand Drive',
   9000, 240,
   'weekly', ARRAY['TU'],
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890'),
  ('e3333333-0000-0000-0000-000000000003',
   'c1111111-0000-0000-0000-000000000001',
   'Thursday 10K shakeout',
   'Social 10K before the weekend long. Chat pace.',
   '2026-04-16T18:00:00Z', 60, 'Domain, Sydney',
   10000, 360,
   null, null,
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890');

-- RSVPs: runner goes to the next Thursday shakeout (<48h from today's seed
-- run) so the Run-tab UpcomingEventCard fires. Alex also goes.
INSERT INTO event_attendees (event_id, user_id, status, instance_start) VALUES
  ('e3333333-0000-0000-0000-000000000003', 'a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'going', '2026-04-16T18:00:00Z'),
  ('e3333333-0000-0000-0000-000000000003', 'b2c3d4e5-f6a7-8901-bcde-f23456789012', 'going', '2026-04-16T18:00:00Z'),
  ('e1111111-0000-0000-0000-000000000001', 'a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'going', '2026-04-19T06:30:00Z'),
  ('e1111111-0000-0000-0000-000000000001', 'b2c3d4e5-f6a7-8901-bcde-f23456789012', 'maybe',  '2026-04-19T06:30:00Z');

-- Club posts — a top-level announcement + a reply so the threaded-reply
-- UI has content on first load.
INSERT INTO club_posts (id, club_id, event_id, event_instance_start, author_id, body, created_at) VALUES
  ('b1111111-0000-0000-0000-000000000001',
   'c1111111-0000-0000-0000-000000000001', null, null,
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
   'Big field expected on Sunday — 40+ RSVPs so far. We''ll split into two paces at the gate. Bring a light layer, 8°C at dawn.',
   '2026-04-14T09:00:00Z'),
  ('b2222222-0000-0000-0000-000000000002',
   'c1111111-0000-0000-0000-000000000001', null, null,
   'b2c3d4e5-f6a7-8901-bcde-f23456789012',
   'Thanks! I''ll aim for the 5:30 group. See you there.',
   '2026-04-14T10:30:00Z'),
  ('b3333333-0000-0000-0000-000000000003',
   'c1111111-0000-0000-0000-000000000001',
   'e3333333-0000-0000-0000-000000000003',
   '2026-04-16T18:00:00Z',
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
   'Rain is forecast for Thursday — we run unless it''s electrical. Layers.',
   '2026-04-15T07:00:00Z');
-- The reply references a top-level post as its parent.
UPDATE club_posts SET parent_post_id = 'b1111111-0000-0000-0000-000000000001'
  WHERE id = 'b2222222-0000-0000-0000-000000000002';

-- ─────────────────────── 7. Training plan ───────────────────────
-- A 12-week half-marathon plan whose start date puts "today" in week 2,
-- so the dashboard + Run-tab today-card + plan-detail progress ring all
-- have something to render on first load. Weeks 0-2 are fully populated
-- with realistic workouts; weeks 3+ seeded as placeholders so the grid
-- displays a full-looking plan.

INSERT INTO training_plans (
  id, user_id, name, goal_event, goal_distance_m, goal_time_seconds,
  start_date, end_date, days_per_week, vdot, current_5k_seconds,
  status, source, rules, notes
) VALUES (
  'a1a1eada-aaaa-0000-0000-000000000001',
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'Sydney Half 2026',
  'distance_half', 21097.5, 5700,    -- 1:35:00 target
  '2026-03-29', '2026-06-20', 5, 52.0, 1320,   -- 22:00 recent 5K
  'active', 'manual',
  '["80% of weekly mileage should be easy","Never increase weekly volume more than 10% week-over-week","Long run is non-negotiable — protect Sunday","Sleep 8 hours through build weeks"]'::jsonb,
  'Goal race: Sydney Half Marathon, 2026-06-21.'
);

-- Twelve weeks of plan_weeks rows. Phases: base 4 / build 5 / peak 2 / race 1.
INSERT INTO plan_weeks (id, plan_id, week_index, phase, target_volume_m, notes) VALUES
  ('a0aa0001-0000-0000-0000-000000000001', 'a1a1eada-aaaa-0000-0000-000000000001',  0, 'base',  40000, null),
  ('a0aa0002-0000-0000-0000-000000000002', 'a1a1eada-aaaa-0000-0000-000000000001',  1, 'base',  45000, null),
  ('a0aa0003-0000-0000-0000-000000000003', 'a1a1eada-aaaa-0000-0000-000000000001',  2, 'base',  50000, null),
  ('a0aa0004-0000-0000-0000-000000000004', 'a1a1eada-aaaa-0000-0000-000000000001',  3, 'base',  42000, 'Step-back week — recover before the next build.'),
  ('a0aa0005-0000-0000-0000-000000000005', 'a1a1eada-aaaa-0000-0000-000000000001',  4, 'build', 55000, null),
  ('a0aa0006-0000-0000-0000-000000000006', 'a1a1eada-aaaa-0000-0000-000000000001',  5, 'build', 60000, null),
  ('a0aa0007-0000-0000-0000-000000000007', 'a1a1eada-aaaa-0000-0000-000000000001',  6, 'build', 62000, null),
  ('a0aa0008-0000-0000-0000-000000000008', 'a1a1eada-aaaa-0000-0000-000000000001',  7, 'build', 52000, 'Step-back week — recover before the next build.'),
  ('a0aa0009-0000-0000-0000-000000000009', 'a1a1eada-aaaa-0000-0000-000000000001',  8, 'build', 65000, null),
  ('a0aa000a-0000-0000-0000-00000000000a', 'a1a1eada-aaaa-0000-0000-000000000001',  9, 'peak',  60000, null),
  ('a0aa000b-0000-0000-0000-00000000000b', 'a1a1eada-aaaa-0000-0000-000000000001', 10, 'taper', 40000, 'Taper — volume down, sharpness stays.'),
  ('a0aa000c-0000-0000-0000-00000000000c', 'a1a1eada-aaaa-0000-0000-000000000001', 11, 'race',  25000, 'Race week — trust the work.');

-- Week 0 (Mar 29 - Apr 4) — completed; workouts linked to real runs where the
-- date matches. Shows how auto-match renders on the plan-detail grid.
INSERT INTO plan_workouts (week_id, scheduled_date, kind, target_distance_m, target_pace_sec_per_km, target_pace_tolerance_sec, pace_zone, notes) VALUES
  ('a0aa0001-0000-0000-0000-000000000001', '2026-03-29', 'long',     12000, 330, 20, 'E',  null),
  ('a0aa0001-0000-0000-0000-000000000001', '2026-03-30', 'rest',     null,  null, null, null, null),
  ('a0aa0001-0000-0000-0000-000000000001', '2026-03-31', 'easy',     6000,  330, 30, 'E',  null),
  ('a0aa0001-0000-0000-0000-000000000001', '2026-04-01', 'easy',     7000,  330, 30, 'E',  null),
  ('a0aa0001-0000-0000-0000-000000000001', '2026-04-02', 'easy',     6000,  330, 30, 'E',  null),
  ('a0aa0001-0000-0000-0000-000000000001', '2026-04-03', 'rest',     null,  null, null, null, null),
  ('a0aa0001-0000-0000-0000-000000000001', '2026-04-04', 'recovery', 5000,  330, 30, 'E',  null);

-- Week 1 (Apr 5 - Apr 11) — completed. Tempo + MP progression example so
-- the pace-progression arrow on the workout-detail page has content.
INSERT INTO plan_workouts (week_id, scheduled_date, kind, target_distance_m, target_pace_sec_per_km, target_pace_end_sec_per_km, target_pace_tolerance_sec, pace_zone, notes, structure) VALUES
  ('a0aa0002-0000-0000-0000-000000000002', '2026-04-05', 'long',     15000, 325, null, 20, 'E', null, null),
  ('a0aa0002-0000-0000-0000-000000000002', '2026-04-06', 'rest',     null,  null, null, null, null, null, null),
  ('a0aa0002-0000-0000-0000-000000000002', '2026-04-07', 'tempo',    10000, 275, 265, 8,  'T', 'Tempo: 6 km @ threshold.',
     '{"warmup":{"distance_m":2000,"pace":"easy"},"steady":{"distance_m":6000,"pace_sec_per_km":270},"cooldown":{"distance_m":2000,"pace":"easy"}}'::jsonb),
  ('a0aa0002-0000-0000-0000-000000000002', '2026-04-08', 'easy',     7000,  325, null, 30, 'E', null, null),
  ('a0aa0002-0000-0000-0000-000000000002', '2026-04-09', 'marathon_pace', 10000, 295, 280, 8, 'MP', '5 km @ goal half-marathon pace.',
     '{"warmup":{"distance_m":2000,"pace":"easy"},"steady":{"distance_m":5000,"pace_sec_per_km":290},"cooldown":{"distance_m":2000,"pace":"easy"}}'::jsonb),
  ('a0aa0002-0000-0000-0000-000000000002', '2026-04-10', 'rest',     null,  null, null, null, null, null, null),
  ('a0aa0002-0000-0000-0000-000000000002', '2026-04-11', 'recovery', 5000,  330, null, 30, 'E', null, null);

-- Week 2 (Apr 12 - Apr 18) — CURRENT week. Wednesday is today (2026-04-15),
-- so seed that as an easy run so the dashboard + Run-tab today-card light up.
INSERT INTO plan_workouts (week_id, scheduled_date, kind, target_distance_m, target_pace_sec_per_km, target_pace_tolerance_sec, pace_zone, notes, structure) VALUES
  ('a0aa0003-0000-0000-0000-000000000003', '2026-04-12', 'long',     17000, 320, 20, 'E', null, null),
  ('a0aa0003-0000-0000-0000-000000000003', '2026-04-13', 'rest',     null,  null, null, null, null, null),
  ('a0aa0003-0000-0000-0000-000000000003', '2026-04-14', 'interval', 12000, 240, 5, 'I', '5× 1000 m @ VO2 with 400 m jog.',
     '{"warmup":{"distance_m":1500,"pace":"easy"},"repeats":{"count":5,"distance_m":1000,"pace_sec_per_km":240,"recovery_distance_m":400,"recovery_pace":"jog"},"cooldown":{"distance_m":1500,"pace":"easy"}}'::jsonb),
  ('a0aa0003-0000-0000-0000-000000000003', '2026-04-15', 'easy',     8000,  320, 30, 'E', 'Keep it comfortable — intervals were yesterday.', null),
  ('a0aa0003-0000-0000-0000-000000000003', '2026-04-16', 'tempo',     10000, 270, 8, 'T', 'Tempo: 6 km @ threshold.',
     '{"warmup":{"distance_m":2000,"pace":"easy"},"steady":{"distance_m":6000,"pace_sec_per_km":270},"cooldown":{"distance_m":2000,"pace":"easy"}}'::jsonb),
  ('a0aa0003-0000-0000-0000-000000000003', '2026-04-17', 'rest',     null,  null, null, null, null, null),
  ('a0aa0003-0000-0000-0000-000000000003', '2026-04-18', 'recovery', 5000,  330, 30, 'E', null, null);

-- Weeks 3-11 — placeholder rows so the plan grid renders fully.
INSERT INTO plan_workouts (week_id, scheduled_date, kind, target_distance_m, target_pace_sec_per_km, target_pace_tolerance_sec, pace_zone) VALUES
  ('a0aa0004-0000-0000-0000-000000000004', '2026-04-19', 'long',     14000, 320, 20, 'E'),
  ('a0aa0004-0000-0000-0000-000000000004', '2026-04-20', 'rest',     null,  null, null, null),
  ('a0aa0004-0000-0000-0000-000000000004', '2026-04-21', 'easy',     7000,  320, 30, 'E'),
  ('a0aa0004-0000-0000-0000-000000000004', '2026-04-22', 'easy',     6000,  320, 30, 'E'),
  ('a0aa0004-0000-0000-0000-000000000004', '2026-04-23', 'easy',     7000,  320, 30, 'E'),
  ('a0aa0004-0000-0000-0000-000000000004', '2026-04-24', 'rest',     null,  null, null, null),
  ('a0aa0004-0000-0000-0000-000000000004', '2026-04-25', 'recovery', 5000,  330, 30, 'E'),

  ('a0aa0005-0000-0000-0000-000000000005', '2026-04-26', 'long',     18000, 320, 20, 'E'),
  ('a0aa0005-0000-0000-0000-000000000005', '2026-04-27', 'rest',     null,  null, null, null),
  ('a0aa0005-0000-0000-0000-000000000005', '2026-04-28', 'interval', 13000, 235, 5,  'I'),
  ('a0aa0005-0000-0000-0000-000000000005', '2026-04-29', 'easy',     8000,  320, 30, 'E'),
  ('a0aa0005-0000-0000-0000-000000000005', '2026-04-30', 'tempo',    11000, 265, 8,  'T'),
  ('a0aa0005-0000-0000-0000-000000000005', '2026-05-01', 'rest',     null,  null, null, null),
  ('a0aa0005-0000-0000-0000-000000000005', '2026-05-02', 'recovery', 5000,  330, 30, 'E'),

  ('a0aa000c-0000-0000-0000-00000000000c', '2026-06-14', 'long',     6000, 330, 20, 'E'),
  ('a0aa000c-0000-0000-0000-00000000000c', '2026-06-15', 'rest',     null,  null, null, null),
  ('a0aa000c-0000-0000-0000-00000000000c', '2026-06-16', 'easy',     5000,  330, 30, 'E'),
  ('a0aa000c-0000-0000-0000-00000000000c', '2026-06-17', 'marathon_pace', 6000, 280, 8, 'MP'),
  ('a0aa000c-0000-0000-0000-00000000000c', '2026-06-18', 'easy',     4000,  330, 30, 'E'),
  ('a0aa000c-0000-0000-0000-00000000000c', '2026-06-19', 'rest',     null,  null, null, null),
  ('a0aa000c-0000-0000-0000-00000000000c', '2026-06-20', 'race',     21097, 270, 5,  'MP');

-- Mark the week-0 long run as auto-matched to the corresponding 21km run
-- that's already in the runs table (2026-03-26 half) — close enough to the
-- Mar 29 long-run date for a "Completed" badge on the grid. Uses whichever
-- run row exists with that date (ordered by started_at desc).
UPDATE plan_workouts pw
SET completed_run_id = (
      SELECT r.id FROM runs r
      WHERE r.user_id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
        AND r.started_at >= '2026-03-29' AND r.started_at < '2026-03-30'
      ORDER BY r.started_at DESC LIMIT 1
    ),
    completed_at = now()
WHERE pw.scheduled_date = '2026-03-29' AND pw.kind = 'long';

-- Same trick for the week-1 long run matching the Apr 5 run if one exists.
UPDATE plan_workouts pw
SET completed_run_id = (
      SELECT r.id FROM runs r
      WHERE r.user_id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
        AND r.started_at >= '2026-04-05' AND r.started_at < '2026-04-06'
      ORDER BY r.started_at DESC LIMIT 1
    ),
    completed_at = now()
WHERE pw.scheduled_date = '2026-04-05' AND pw.kind = 'long';

-- ─────────────────────────────────────────────────────────────────────
-- 11. Social-feed seeding for runner@test.com
--
-- Runner has 173 public runs of their own but follows nobody, so /feed
-- is empty when logged in as runner. Add a third seed user (Morgan)
-- plus a small pile of recent public runs for both Alex and Morgan,
-- and have runner follow both of them. Result:
--   - runner sees ~25 entries in /feed → /feed cursor pagination (20
--     per page within the 14-day window) needs a "Load more" click.
--   - the feed visibly mixes two authors so the per-entry author
--     avatar / name UI is exercised, not just one-author monotony.
-- ─────────────────────────────────────────────────────────────────────

-- Morgan, the third seed user. testtest password, same shape as Alex.
INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change_token_current,
  email_change, phone, phone_change, phone_change_token, reauthentication_token,
  is_sso_user, is_anonymous, raw_app_meta_data, raw_user_meta_data
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  'c3d4e5f6-a7b8-9012-cdef-345678901234',
  'authenticated', 'authenticated',
  'morgan@test.com',
  extensions.crypt('testtest', extensions.gen_salt('bf')),
  now(), now(), now(),
  '', '', '', '',
  '', NULL, '', '', '',
  false, false,
  '{"provider":"email","providers":["email"]}',
  '{"email_verified":true}'
) ON CONFLICT (id) DO NOTHING;

INSERT INTO auth.identities (
  id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
) VALUES (
  'c3d4e5f6-a7b8-9012-cdef-345678901234',
  'c3d4e5f6-a7b8-9012-cdef-345678901234',
  'c3d4e5f6-a7b8-9012-cdef-345678901234',
  jsonb_build_object('sub', 'c3d4e5f6-a7b8-9012-cdef-345678901234', 'email', 'morgan@test.com', 'email_verified', true),
  'email', now(), now(), now()
) ON CONFLICT DO NOTHING;

INSERT INTO user_profiles (id, display_name, preferred_unit, subscription_tier)
VALUES ('c3d4e5f6-a7b8-9012-cdef-345678901234', 'Morgan Lee', 'km', 'free')
ON CONFLICT (id) DO NOTHING;

-- Recent public runs for Alex — 12 entries spread across the last
-- ~7 days so the feed has variety even before pagination kicks in.
-- Anchored on NOW() (not a fixed timestamp) so the entries stay inside
-- the 14-day FEED_WINDOW as real wall-clock time advances past the
-- frozen 2026-04-26 "today" the rest of the seed uses.
INSERT INTO runs (user_id, started_at, duration_s, distance_m, source, is_public, metadata)
SELECT
  'b2c3d4e5-f6a7-8901-bcde-f23456789012'::uuid,
  (NOW() - (n * INTERVAL '14 hours')),
  (1800 + (n * 173 % 2400))::integer,
  (5000 + (n * 251 % 8000))::numeric,
  CASE n % 3 WHEN 0 THEN 'app' WHEN 1 THEN 'strava' ELSE 'healthkit' END,
  true,
  jsonb_build_object(
    'activity_type', 'run',
    'avg_bpm', 152 + (n % 22),
    'perceived_effort', 4 + (n % 4)
  )
FROM generate_series(1, 12) AS n;

-- Recent public runs for Morgan — 13 entries on a different cadence
-- so the feed mixes the two authors rather than alternating cleanly.
-- Same NOW()-relative anchor as Alex above; see comment there.
INSERT INTO runs (user_id, started_at, duration_s, distance_m, source, is_public, metadata)
SELECT
  'c3d4e5f6-a7b8-9012-cdef-345678901234'::uuid,
  (NOW() - INTERVAL '4 hours' - (n * INTERVAL '17 hours')),
  (1500 + (n * 197 % 2700))::integer,
  (4500 + (n * 293 % 9500))::numeric,
  CASE n % 4 WHEN 0 THEN 'app' WHEN 1 THEN 'app' WHEN 2 THEN 'strava' ELSE 'parkrun' END,
  true,
  jsonb_build_object(
    'activity_type', 'run',
    'avg_bpm', 148 + (n % 28),
    'perceived_effort', 4 + (n % 5)
  )
FROM generate_series(1, 13) AS n;

-- The follow graph that surfaces all of the above on runner's /feed.
-- Two-way alex ↔ runner so social-loop testing flows both directions.
INSERT INTO user_follows (follower_id, followee_id) VALUES
  ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'b2c3d4e5-f6a7-8901-bcde-f23456789012'),
  ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'c3d4e5f6-a7b8-9012-cdef-345678901234'),
  ('b2c3d4e5-f6a7-8901-bcde-f23456789012', 'a1b2c3d4-e5f6-7890-abcd-ef1234567890')
ON CONFLICT DO NOTHING;

-- ─────────────────────── e2e fixtures ───────────────────────
--
-- Additions for the Playwright e2e suite (apps/web/tests-e2e/).
-- The three users runner / alex / morgan and their public runs are
-- already seeded above; this section only fills the gaps the suite
-- needs:
--
--   1. A private run on alex's account so the cross-user-isolation
--      test has a target to assert "non-owner cannot see this".
--   2. A privacy_zones entry on runner's settings so the zones-picker
--      UI has content + non-owner share-page tests have something to
--      assert clipping against.
--   3. Morgan upgraded from 'free' to 'pro' so paywall-tier tests
--      have a positive control. The lock_subscription_columns trigger
--      bypasses on the empty-role context that seed.sql runs in
--      (request.jwt.claim.role is unset → bypasses; see migration
--      20260429_001).
--   4. A kudos + comment from alex on one of runner's public runs so
--      the cross-user engagement-chain UI surfaces have content
--      without needing to drive the action through the app.
--
-- All `ON CONFLICT DO NOTHING` so the section is idempotent — re-runs
-- via `supabase db reset` don't trip unique-constraint errors.

-- 1. Alex's private run.
INSERT INTO runs (id, user_id, started_at, duration_s, distance_m, source, is_public, metadata)
VALUES (
  'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
  'b2c3d4e5-f6a7-8901-bcde-f23456789012',
  '2026-04-25T07:00:00Z',
  2400, 7500, 'app',
  false,
  jsonb_build_object(
    'activity_type', 'run',
    'avg_bpm', 156,
    'perceived_effort', 5,
    'title', 'Recovery jog (private)'
  )
) ON CONFLICT (id) DO NOTHING;

-- 1b. A pinned runner public run so e2e specs can navigate to a known
-- /runs/<id> and /share/run/<id> URL without first scraping the runs
-- list. Dated newest so it sorts to the top of /runs and /feed without
-- displacing the auto-id'd 12.
INSERT INTO runs (id, user_id, started_at, duration_s, distance_m, source, is_public, metadata)
VALUES (
  '11112222-3333-4444-5555-666677778888',
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  '2026-04-28T08:00:00Z',
  2700, 9000, 'app',
  true,
  jsonb_build_object(
    'activity_type', 'run',
    'avg_bpm', 152,
    'perceived_effort', 4,
    'title', 'E2E demo public run'
  )
) ON CONFLICT (id) DO NOTHING;

-- 1c. A pinned runner public route so /share/route/<id> anon tests
-- have a known target. Mirrors 1b's shape — explicit UUID so the test
-- doesn't have to scrape /routes first to find a public one.
INSERT INTO routes (id, user_id, name, distance_m, elevation_m, surface, is_public, waypoints)
VALUES (
  '22223333-4444-5555-6666-777788889999',
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'E2E demo public route',
  10000, 50, 'road', true,
  '[{"lat":-37.8200,"lng":144.9700,"ele":20},{"lat":-37.8180,"lng":144.9720,"ele":25},{"lat":-37.8160,"lng":144.9740,"ele":30},{"lat":-37.8140,"lng":144.9760,"ele":35},{"lat":-37.8120,"lng":144.9780,"ele":40},{"lat":-37.8100,"lng":144.9800,"ele":45}]'::jsonb
) ON CONFLICT (id) DO NOTHING;

-- 2. Privacy zone on runner's settings. The existing INSERT at the top
-- of seed.sql sets the rest of runner's prefs; we merge the zone in
-- via prefs || jsonb_build_object so we don't lose date_of_birth /
-- HR config / etc.
UPDATE user_settings
   SET prefs = prefs || jsonb_build_object(
     'privacy_zones', jsonb_build_array(
       jsonb_build_object(
         'lat', -37.8136, 'lng', 144.9631, 'radius_m', 200,
         'label', 'home'
       )
     )
   )
 WHERE user_id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';

-- 3. Morgan upgraded to pro.
UPDATE user_profiles
   SET subscription_tier = 'pro'
 WHERE id = 'c3d4e5f6-a7b8-9012-cdef-345678901234';

-- 4. Cross-user engagement on one of runner's public runs. Pick the
-- most recent UNLESS it's the pinned RUNNER_PUBLIC_RUN_ID — that one
-- is reserved for the data-flow Playwright spec which toggles kudos
-- on/off and needs a clean starting state. Filtering it out leaves
-- engagement on a different runner run, so the engagement-chain UI
-- still has content to render on share pages + run-detail.
INSERT INTO run_kudos (user_id, run_id)
SELECT 'b2c3d4e5-f6a7-8901-bcde-f23456789012', id
  FROM runs
 WHERE user_id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
   AND is_public = true
   AND id != '11112222-3333-4444-5555-666677778888'
 ORDER BY started_at DESC
 LIMIT 1
ON CONFLICT DO NOTHING;

INSERT INTO run_comments (run_id, author_id, body)
SELECT id, 'b2c3d4e5-f6a7-8901-bcde-f23456789012', 'Strong work — that pace looked easy at the end!'
  FROM runs
 WHERE user_id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
   AND is_public = true
   AND id != '11112222-3333-4444-5555-666677778888'
 ORDER BY started_at DESC
 LIMIT 1;

-- ─────────────────────── Regression tests ───────────────────────
--
-- Inline assertions that fire on every `supabase db reset`. These
-- exercise the SECURITY DEFINER + crypto-sensitive paths that Edge
-- Function CI doesn't cover. A failure here means a migration that
-- landed (or modified) one of these functions changed its contract —
-- catch it before any caller does.
--
-- Lives in seed.sql rather than a migration so the assertions don't
-- run in production deploys. seed.sql only fires on local
-- `db reset`; production migrations skip it entirely.

-- ───────── check_rate_limit (migration 20260604_001) ─────────
-- Mocks the JWT context per call (migration 20260614_001 added a
-- caller-identity guard: auth.uid() must match p_user_id).
DO $$
DECLARE
  test_user uuid := '99999999-9999-9999-9999-999999999991';
  test_user2 uuid := '99999999-9999-9999-9999-999999999992';
  v_allowed boolean;
  v_retry integer;
BEGIN
  DELETE FROM rate_limits WHERE user_id IN (test_user, test_user2);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', test_user::text, true);

  -- 1st + 2nd within max → allow.
  SELECT allowed INTO v_allowed FROM check_rate_limit(test_user, 'test_rl', 2, 3600);
  IF NOT v_allowed THEN RAISE EXCEPTION 'check_rate_limit: 1st call should allow'; END IF;
  SELECT allowed INTO v_allowed FROM check_rate_limit(test_user, 'test_rl', 2, 3600);
  IF NOT v_allowed THEN RAISE EXCEPTION 'check_rate_limit: 2nd call should allow'; END IF;

  -- 3rd exceeds → deny with retry_after > 0.
  SELECT allowed, retry_after_seconds INTO v_allowed, v_retry
    FROM check_rate_limit(test_user, 'test_rl', 2, 3600);
  IF v_allowed OR v_retry <= 0 THEN
    RAISE EXCEPTION 'check_rate_limit: 3rd call should deny w/ retry_after>0, got allowed=% retry=%', v_allowed, v_retry;
  END IF;

  -- Per-user isolation — test_user2 starts fresh.
  PERFORM set_config('request.jwt.claim.sub', test_user2::text, true);
  SELECT allowed INTO v_allowed FROM check_rate_limit(test_user2, 'test_rl', 2, 3600);
  IF NOT v_allowed THEN RAISE EXCEPTION 'check_rate_limit: per-user counter leaked'; END IF;

  -- Per-bucket isolation — same user, different bucket starts fresh.
  PERFORM set_config('request.jwt.claim.sub', test_user::text, true);
  SELECT allowed INTO v_allowed FROM check_rate_limit(test_user, 'test_rl_other', 2, 3600);
  IF NOT v_allowed THEN RAISE EXCEPTION 'check_rate_limit: per-bucket counter leaked'; END IF;

  -- Input validation: max=0 raises.
  BEGIN
    PERFORM check_rate_limit(test_user, 'test_rl', 0, 3600);
    RAISE EXCEPTION 'check_rate_limit: max=0 should have raised';
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM NOT LIKE '%must be positive%' THEN
        RAISE EXCEPTION 'check_rate_limit raised wrong error: %', SQLERRM;
      END IF;
  END;

  -- Caller-identity guard: passing a foreign p_user_id raises.
  BEGIN
    PERFORM check_rate_limit(test_user2, 'test_rl', 2, 3600);
    RAISE EXCEPTION 'check_rate_limit: foreign p_user_id should have raised';
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM NOT LIKE '%not authorized%' THEN
        RAISE EXCEPTION 'check_rate_limit caller-guard raised wrong error: %', SQLERRM;
      END IF;
  END;

  DELETE FROM rate_limits WHERE user_id IN (test_user, test_user2);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
END $$;

-- Service-role escape hatch (migration 20260616_001): a service-role
-- caller can pass any p_user_id; the auth.uid() guard is bypassed.
DO $$
DECLARE
  test_user uuid := '99999999-9999-9999-9999-999999999991';
  test_user2 uuid := '99999999-9999-9999-9999-999999999992';
  v_allowed boolean;
BEGIN
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT allowed INTO v_allowed FROM check_rate_limit(test_user, 'svc_rl', 2, 3600);
  IF NOT v_allowed THEN RAISE EXCEPTION 'check_rate_limit: service role 1st call should allow'; END IF;
  SELECT allowed INTO v_allowed FROM check_rate_limit(test_user2, 'svc_rl', 2, 3600);
  IF NOT v_allowed THEN RAISE EXCEPTION 'check_rate_limit: service role on second user should allow'; END IF;

  DELETE FROM rate_limits WHERE user_id IN (test_user, test_user2);
  PERFORM set_config('request.jwt.claim.role', '', true);
END $$;

-- ───────── check_rate_limit_tiered (migration 20260605_001) ─────────
-- Mocks the JWT context (migration 20260614_001 added a caller-
-- identity guard: auth.uid() must match p_user_id).
DO $$
DECLARE
  test_user uuid := 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';  -- runner@test.com
  test_bucket text := 'tiered_test';
  v_allowed boolean;
  v_tier text;
  v_initial_tier text;
BEGIN
  -- Snapshot the seed user's tier so we can restore it; the seed
  -- defaults to 'free' but we don't want this test to silently
  -- depend on that.
  SELECT subscription_tier INTO v_initial_tier FROM user_profiles WHERE id = test_user;
  DELETE FROM rate_limits WHERE user_id = test_user AND bucket = test_bucket;

  -- Tier flips bracket the role: switch to service_role for the UPDATE
  -- (the lock_subscription_columns trigger from 20260624_001 only
  -- accepts service_role / direct-SQL writers), then back to
  -- authenticated for the rate-limit assertion which exercises the
  -- caller-identity guard.
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  UPDATE user_profiles SET subscription_tier = 'free' WHERE id = test_user;

  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', test_user::text, true);

  -- Free user: limit (free=2, pro=10) — 3rd call denies.
  SELECT allowed INTO v_allowed FROM check_rate_limit_tiered(test_user, test_bucket, 2, 10, 3600);
  IF NOT v_allowed THEN RAISE EXCEPTION 'tiered: free 1st call should allow'; END IF;
  SELECT allowed INTO v_allowed FROM check_rate_limit_tiered(test_user, test_bucket, 2, 10, 3600);
  IF NOT v_allowed THEN RAISE EXCEPTION 'tiered: free 2nd call should allow'; END IF;
  SELECT allowed, tier INTO v_allowed, v_tier
    FROM check_rate_limit_tiered(test_user, test_bucket, 2, 10, 3600);
  IF v_allowed THEN RAISE EXCEPTION 'tiered: free 3rd call should deny'; END IF;
  IF v_tier <> 'free' THEN RAISE EXCEPTION 'tiered: free user tier echo wrong, got %', v_tier; END IF;

  DELETE FROM rate_limits WHERE user_id = test_user AND bucket = test_bucket;

  -- Pro user: same params, 11th call denies.
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  UPDATE user_profiles SET subscription_tier = 'pro' WHERE id = test_user;
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  FOR i IN 1..10 LOOP
    SELECT allowed INTO v_allowed FROM check_rate_limit_tiered(test_user, test_bucket, 2, 10, 3600);
    IF NOT v_allowed THEN RAISE EXCEPTION 'tiered: pro call % should allow', i; END IF;
  END LOOP;
  SELECT allowed, tier INTO v_allowed, v_tier
    FROM check_rate_limit_tiered(test_user, test_bucket, 2, 10, 3600);
  IF v_allowed THEN RAISE EXCEPTION 'tiered: pro 11th call should deny'; END IF;
  IF v_tier <> 'pro' THEN RAISE EXCEPTION 'tiered: pro user tier echo wrong, got %', v_tier; END IF;

  DELETE FROM rate_limits WHERE user_id = test_user AND bucket = test_bucket;

  -- Lifetime treated identically to pro (gets the higher ceiling).
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  UPDATE user_profiles SET subscription_tier = 'lifetime' WHERE id = test_user;
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  FOR i IN 1..10 LOOP
    SELECT allowed INTO v_allowed FROM check_rate_limit_tiered(test_user, test_bucket, 2, 10, 3600);
    IF NOT v_allowed THEN RAISE EXCEPTION 'tiered: lifetime call % should allow (treated as pro)', i; END IF;
  END LOOP;

  DELETE FROM rate_limits WHERE user_id = test_user AND bucket = test_bucket;

  -- Input validation: any non-positive arg raises.
  BEGIN
    PERFORM check_rate_limit_tiered(test_user, test_bucket, 0, 10, 3600);
    RAISE EXCEPTION 'tiered: free_max=0 should have raised';
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM NOT LIKE '%must be positive%' THEN
        RAISE EXCEPTION 'tiered: free_max=0 raised wrong error: %', SQLERRM;
      END IF;
  END;

  -- Restore the seed-time tier so downstream tests don't see drift.
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  UPDATE user_profiles SET subscription_tier = v_initial_tier WHERE id = test_user;
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
END $$;

-- ───────── integrations vault (migration 20260603_001) ─────────
-- Uses runner@test.com + provider='runsignup' (a valid value per the
-- 20260505_001 CHECK constraint that the seed doesn't exercise) so
-- the test row doesn't collide with the seeded parkrun / strava
-- integrations and cleans up at the end. integrations.user_id
-- references auth.users so we have to use an existing seeded user.
DO $$
DECLARE
  test_user uuid := 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
  test_provider text := 'runsignup';
  v_access text;
  v_refresh text;
  v_id_before uuid;
  v_id_after uuid;
BEGIN
  -- Service role bypasses the SECURITY DEFINER owner check.
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);

  DELETE FROM integrations WHERE user_id = test_user AND provider = test_provider;

  -- Round-trip on first insert.
  PERFORM set_integration_tokens(
    test_user, test_provider, 'access_v1', 'refresh_v1',
    now() + interval '6 hours'
  );
  SELECT access_token, refresh_token INTO v_access, v_refresh
    FROM get_integration_tokens(test_user, test_provider);
  IF v_access IS DISTINCT FROM 'access_v1' OR v_refresh IS DISTINCT FROM 'refresh_v1' THEN
    RAISE EXCEPTION 'integrations vault: expected (access_v1, refresh_v1), got (%, %)', v_access, v_refresh;
  END IF;

  -- secret_id stays stable across rotation. The setter calls
  -- vault.update_secret in place rather than create_secret so any
  -- caller cached-reference still resolves after a token refresh.
  SELECT access_token_secret_id INTO v_id_before
    FROM integrations WHERE user_id = test_user AND provider = test_provider;
  IF v_id_before IS NULL THEN RAISE EXCEPTION 'secret_id should populate'; END IF;

  PERFORM set_integration_tokens(test_user, test_provider, 'access_v2', 'refresh_v2', NULL);
  SELECT access_token_secret_id INTO v_id_after
    FROM integrations WHERE user_id = test_user AND provider = test_provider;
  IF v_id_after IS DISTINCT FROM v_id_before THEN
    RAISE EXCEPTION 'integrations vault: secret_id should stay stable across rotation, was % now %', v_id_before, v_id_after;
  END IF;

  SELECT access_token, refresh_token INTO v_access, v_refresh
    FROM get_integration_tokens(test_user, test_provider);
  IF v_access IS DISTINCT FROM 'access_v2' OR v_refresh IS DISTINCT FROM 'refresh_v2' THEN
    RAISE EXCEPTION 'integrations vault rotation: expected (access_v2, refresh_v2), got (%, %)', v_access, v_refresh;
  END IF;

  -- Structural check: the row carries vault refs, not plaintext.
  PERFORM 1 FROM integrations
    WHERE user_id = test_user AND provider = test_provider
      AND access_token_secret_id IS NOT NULL
      AND refresh_token_secret_id IS NOT NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'integrations row missing vault refs after set'; END IF;

  DELETE FROM integrations WHERE user_id = test_user AND provider = test_provider;
  PERFORM set_config('request.jwt.claim.role', '', true);
END $$;

-- ───────── cross-user auth gate ─────────
DO $$
DECLARE
  victim_user uuid := 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';  -- runner@test.com
  v_text text;
BEGIN
  -- Simulate an authenticated non-owner. auth.uid() reads from
  -- request.jwt.claim.sub; setting it to a different UUID makes the
  -- SECURITY DEFINER function see "caller != owner".
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000000', true);

  BEGIN
    SELECT access_token INTO v_text FROM get_integration_tokens(victim_user, 'strava');
    RAISE EXCEPTION 'cross-user get_integration_tokens should have raised';
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM NOT LIKE '%forbidden%' THEN
        RAISE EXCEPTION 'cross-user read raised wrong error: %', SQLERRM;
      END IF;
  END;

  BEGIN
    PERFORM set_integration_tokens(victim_user, 'strava', 'a', 'b', NULL);
    RAISE EXCEPTION 'cross-user set_integration_tokens should have raised';
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM NOT LIKE '%forbidden%' THEN
        RAISE EXCEPTION 'cross-user write raised wrong error: %', SQLERRM;
      END IF;
  END;

  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
END $$;

-- ───────── runs.track_url path-shape CHECK (migration 20260621_001) ─────────
-- Verifies an attacker can't rewrite their own row's track_url to
-- point at another user's blob — the CHECK rejects any path that
-- isn't the canonical {user_id}/{run_id}.json.gz.
DO $$
DECLARE
  test_user uuid := 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
  test_run_id uuid;
BEGIN
  -- Pick the OLDEST run by started_at so the test always lands on
  -- one of the original London/Melbourne seed rows and never on one
  -- of the newer Virginia seed rows (a1000001-…) which carry real
  -- gzipped track files uploaded by `npm run dev:db:seed-tracks`.
  -- Without ORDER BY, the LIMIT 1 picked an unspecified row — which
  -- landed on a Virginia run and the line ~1147 `UPDATE … SET
  -- track_url = NULL` below stripped its track_url, leaving the
  -- run-detail map blank.
  SELECT id INTO test_run_id FROM runs
    WHERE user_id = test_user ORDER BY started_at LIMIT 1;

  -- Canonical shape — must succeed.
  UPDATE runs SET track_url = test_user::text || '/' || test_run_id::text || '.json.gz'
    WHERE id = test_run_id;

  -- Foreign user's path — must raise.
  BEGIN
    UPDATE runs
      SET track_url = '99999999-9999-9999-9999-999999999991/'
                      || test_run_id::text || '.json.gz'
      WHERE id = test_run_id;
    RAISE EXCEPTION 'runs_track_url_path_shape: foreign-user path should have been rejected';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  -- Foreign run id — must raise.
  BEGIN
    UPDATE runs
      SET track_url = test_user::text
                      || '/99999999-9999-9999-9999-999999999991.json.gz'
      WHERE id = test_run_id;
    RAISE EXCEPTION 'runs_track_url_path_shape: foreign-run path should have been rejected';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  -- NULL is fine (no track yet). Leave the test_run_id row with a
  -- NULL track_url after the CHECK exercise — seed.sql does NOT
  -- upload an actual Storage file for it, so a non-null canonical
  -- track_url would make the dashboard / detail page's
  -- `fetchTrack` 404 on Storage instead of returning [] for the
  -- seed user. (The earlier comment about needing to "restore
  -- canonical for the live_run_pings downstream test" was wrong —
  -- that test only references `test_run_id`, never `track_url`.)
  UPDATE runs SET track_url = NULL WHERE id = test_run_id;
END $$;

-- ───────── run_photos.storage_path path-shape CHECK (migration 20260622_001) ─────────
-- Verifies an owner can't rewrite their own row's storage_path to
-- point at another user's blob — the CHECK rejects any non-empty
-- value that doesn't start with owner_id/.
DO $$
DECLARE
  test_user uuid := 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
  test_run_id uuid;
  test_photo_id uuid;
BEGIN
  -- Pick the OLDEST run by started_at so the test always lands on
  -- one of the original London/Melbourne seed rows and never on one
  -- of the newer Virginia seed rows (a1000001-…) which carry real
  -- gzipped track files uploaded by `npm run dev:db:seed-tracks`.
  -- Without ORDER BY, the LIMIT 1 picked an unspecified row — which
  -- landed on a Virginia run and the line ~1147 `UPDATE … SET
  -- track_url = NULL` below stripped its track_url, leaving the
  -- run-detail map blank.
  SELECT id INTO test_run_id FROM runs
    WHERE user_id = test_user ORDER BY started_at LIMIT 1;
  test_photo_id := gen_random_uuid();

  -- Insert with the transient empty-string placeholder used by the
  -- mobile addRunPhoto flow — must succeed.
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', test_user::text, true);
  INSERT INTO run_photos (id, run_id, owner_id, storage_path, position_idx)
    VALUES (test_photo_id, test_run_id, test_user, '', 0);

  -- Update to a foreign-owner path — must raise.
  BEGIN
    UPDATE run_photos
      SET storage_path = '99999999-9999-9999-9999-999999999991/'
                         || test_photo_id::text || '.jpg'
      WHERE id = test_photo_id;
    RAISE EXCEPTION 'run_photos_storage_path_shape: foreign-owner path should have been rejected';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  -- Update to a path missing the owner-prefix — must raise.
  BEGIN
    UPDATE run_photos
      SET storage_path = 'somefolder/' || test_photo_id::text || '.jpg'
      WHERE id = test_photo_id;
    RAISE EXCEPTION 'run_photos_storage_path_shape: prefixless path should have been rejected';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  -- Canonical path — must succeed.
  UPDATE run_photos
    SET storage_path = test_user::text || '/' || test_photo_id::text || '.jpg'
    WHERE id = test_photo_id;

  -- Cleanup.
  DELETE FROM run_photos WHERE id = test_photo_id;
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
END $$;

-- ───────── live_run_pings privacy clipping (migration 20260618_001) ─────────
-- Verifies the BEFORE INSERT trigger drops pings inside any of the
-- runner's privacy zones — the surface that Realtime broadcasts to
-- /live/{run_id} subscribers.
DO $$
DECLARE
  test_user uuid := 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
  test_run_id uuid;
  v_count_before int;
  v_count_after int;
  v_zones_before jsonb;
BEGIN
  SELECT prefs->'privacy_zones' INTO v_zones_before
    FROM user_settings WHERE user_id = test_user;

  UPDATE user_settings
    SET prefs = prefs || jsonb_build_object(
      'privacy_zones',
      jsonb_build_array(jsonb_build_object('lat', 40.0, 'lng', -74.0, 'radius_m', 200))
    )
    WHERE user_id = test_user;

  -- Pick the OLDEST run by started_at so the test always lands on
  -- one of the original London/Melbourne seed rows and never on one
  -- of the newer Virginia seed rows (a1000001-…) which carry real
  -- gzipped track files uploaded by `npm run dev:db:seed-tracks`.
  -- Without ORDER BY, the LIMIT 1 picked an unspecified row — which
  -- landed on a Virginia run and the line ~1147 `UPDATE … SET
  -- track_url = NULL` below stripped its track_url, leaving the
  -- run-detail map blank.
  SELECT id INTO test_run_id FROM runs
    WHERE user_id = test_user ORDER BY started_at LIMIT 1;
  DELETE FROM live_run_pings WHERE run_id = test_run_id;

  SELECT count(*) INTO v_count_before FROM live_run_pings WHERE run_id = test_run_id;

  -- Out-of-zone ping (~5km north): should land.
  INSERT INTO live_run_pings (run_id, user_id, lat, lng)
    VALUES (test_run_id, test_user, 40.045, -74.0);

  -- In-zone ping (~55m offset): should be silently dropped by the trigger.
  INSERT INTO live_run_pings (run_id, user_id, lat, lng)
    VALUES (test_run_id, test_user, 40.0005, -74.0);

  SELECT count(*) INTO v_count_after FROM live_run_pings WHERE run_id = test_run_id;
  IF v_count_after - v_count_before <> 1 THEN
    RAISE EXCEPTION 'live_run_pings privacy trigger: expected exactly 1 ping to land (out-of-zone only), got delta=%', v_count_after - v_count_before;
  END IF;

  DELETE FROM live_run_pings WHERE run_id = test_run_id;
  UPDATE user_settings
    SET prefs = case
      when v_zones_before is null then prefs - 'privacy_zones'
      else prefs || jsonb_build_object('privacy_zones', v_zones_before)
    end
    WHERE user_id = test_user;
END $$;

-- ───────── webhook_events dedupe (migration 20260623_001) ─────────
DO $$
DECLARE
  v_pk_violation_caught boolean := false;
BEGIN
  INSERT INTO webhook_events (provider, event_id)
    VALUES ('revenuecat', 'evt-seed-test-1');

  BEGIN
    INSERT INTO webhook_events (provider, event_id)
      VALUES ('revenuecat', 'evt-seed-test-1');
  EXCEPTION
    WHEN unique_violation THEN
      v_pk_violation_caught := true;
  END;

  IF NOT v_pk_violation_caught THEN
    RAISE EXCEPTION 'webhook_events: duplicate (provider,event_id) should have raised unique_violation';
  END IF;

  -- Different provider with the same id is allowed — namespaces don't
  -- collide.
  INSERT INTO webhook_events (provider, event_id)
    VALUES ('stripe', 'evt-seed-test-1');

  DELETE FROM webhook_events WHERE event_id = 'evt-seed-test-1';
END $$;

-- ───────── lock_subscription_columns (migration 20260624_001) ─────────
-- A free user must not be able to self-promote subscription_tier or
-- forge subscription_at via a direct PostgREST PATCH. The trigger
-- raises 42501 for any non-service-role caller; service-role and
-- direct-SQL callers (no JWT context) pass through.
DO $$
DECLARE
  test_user uuid := 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
  v_initial_tier text;
  v_initial_at timestamptz;
  v_after_tier text;
BEGIN
  SELECT subscription_tier, subscription_at INTO v_initial_tier, v_initial_at
    FROM user_profiles WHERE id = test_user;

  -- Authenticated user-JWT context: tier write must raise.
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', test_user::text, true);

  BEGIN
    UPDATE user_profiles SET subscription_tier = 'pro' WHERE id = test_user;
    RAISE EXCEPTION 'lock_subscription_columns: authenticated tier write should have raised';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  -- subscription_at must be locked too.
  BEGIN
    UPDATE user_profiles SET subscription_at = now() WHERE id = test_user;
    RAISE EXCEPTION 'lock_subscription_columns: authenticated subscription_at write should have raised';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  -- Non-tier columns must still be writable for the owner.
  UPDATE user_profiles SET display_name = 'Trigger Test' WHERE id = test_user;

  -- Service-role: tier write must succeed.
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  UPDATE user_profiles SET subscription_tier = 'pro' WHERE id = test_user;
  SELECT subscription_tier INTO v_after_tier FROM user_profiles WHERE id = test_user;
  IF v_after_tier <> 'pro' THEN
    RAISE EXCEPTION 'lock_subscription_columns: service-role write didn''t land, got %', v_after_tier;
  END IF;

  -- Restore.
  UPDATE user_profiles
    SET subscription_tier = v_initial_tier, subscription_at = v_initial_at, display_name = 'Jared Howard'
    WHERE id = test_user;
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
END $$;

-- ───────── clip_route_for_viewer (migration 20260625_001) ─────────
-- Mirrors the runs-side clip_track_for_user contract for routes:
-- owner gets unclipped waypoints, non-owner gets clipped output, anon
-- can read public-only and is treated as non-owner. The clip step
-- delegates to clip_track_for_user so this test exercises the routes
-- gating layer specifically (visibility check + owner detection).
DO $$
DECLARE
  test_user uuid := 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';  -- runner@test.com
  other_user uuid := '00000000-0000-0000-0000-000000000099';
  test_route uuid;
  v_zones_before jsonb;
  v_waypoints jsonb := jsonb_build_array(
    jsonb_build_object('lat', 40.0,    'lng', -74.0),    -- in zone (centre)
    jsonb_build_object('lat', 40.0001, 'lng', -74.0),    -- in zone (~11 m N)
    jsonb_build_object('lat', 40.05,   'lng', -74.0),    -- out of zone (~5 km N)
    jsonb_build_object('lat', 40.1,    'lng', -74.0),    -- out of zone
    jsonb_build_object('lat', 40.0001, 'lng', -74.0)     -- in zone (trailing)
  );
  v_owner_result jsonb;
  v_anon_result jsonb;
BEGIN
  -- Stash existing zones, install a 100 m zone at (40, -74).
  SELECT prefs->'privacy_zones' INTO v_zones_before
    FROM user_settings WHERE user_id = test_user;

  UPDATE user_settings
    SET prefs = prefs || jsonb_build_object(
      'privacy_zones',
      jsonb_build_array(
        jsonb_build_object('lat', 40.0, 'lng', -74.0, 'radius_m', 100)
      )
    )
    WHERE user_id = test_user;

  -- Create a public test route owned by runner@test.com with the
  -- waypoints above (some inside the zone, some outside).
  INSERT INTO routes (user_id, name, distance_m, is_public, waypoints)
    VALUES (test_user, 'clip_route_for_viewer test', 1234, true, v_waypoints)
    RETURNING id INTO test_route;

  -- Owner caller: must receive the full unclipped array.
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', test_user::text, true);
  v_owner_result := clip_route_for_viewer(test_route);
  IF jsonb_array_length(v_owner_result) <> 5 THEN
    RAISE EXCEPTION 'clip_route_for_viewer: owner should see all 5 points, got %', jsonb_array_length(v_owner_result);
  END IF;

  -- Anon caller: public route is visible, but waypoints must be
  -- clipped. The contiguous middle is points 2 + 3 (indices 2..3),
  -- so we expect 2 entries.
  PERFORM set_config('request.jwt.claim.role', 'anon', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  v_anon_result := clip_route_for_viewer(test_route);
  IF jsonb_array_length(v_anon_result) <> 2 THEN
    RAISE EXCEPTION 'clip_route_for_viewer: anon should see 2 clipped points, got %', jsonb_array_length(v_anon_result);
  END IF;

  -- Flip route to private. Anon must now be rejected (42501).
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  UPDATE routes SET is_public = false WHERE id = test_route;
  PERFORM set_config('request.jwt.claim.role', 'anon', true);

  BEGIN
    PERFORM clip_route_for_viewer(test_route);
    RAISE EXCEPTION 'clip_route_for_viewer: anon read of private route should have raised';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  -- Authenticated non-owner of a private route: also rejected.
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', other_user::text, true);
  BEGIN
    PERFORM clip_route_for_viewer(test_route);
    RAISE EXCEPTION 'clip_route_for_viewer: non-owner read of private route should have raised';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  -- Missing route: P0002.
  BEGIN
    PERFORM clip_route_for_viewer('00000000-0000-0000-0000-000000000000');
    RAISE EXCEPTION 'clip_route_for_viewer: missing route should have raised';
  EXCEPTION
    WHEN no_data_found THEN NULL;
  END;

  -- Cleanup. Service role flip needed for the route delete + tier
  -- columns aren't touched here but restore zones cleanly.
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  DELETE FROM routes WHERE id = test_route;
  UPDATE user_settings
    SET prefs = case
      when v_zones_before is null then prefs - 'privacy_zones'
      else prefs || jsonb_build_object('privacy_zones', v_zones_before)
    end
    WHERE user_id = test_user;
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
END $$;

-- ───────── public_runs view projection (migration 20260626_001) ─────────
-- Pre-prod public-rows audit fix. Verifies the view:
--   1. exposes only is_public=true rows
--   2. omits external_id from the projection (compile-time guard via column-not-found)
--   3. strips audit / sync / training-plan keys from metadata
--   4. preserves public-safe keys (activity_type, title, etc.)
--   5. nulls route_id when the joined route is private
--   6. nulls event_id when the joined event's club is private
DO $$
DECLARE
  test_user uuid := 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
  v_run_id uuid;
  v_private_route_id uuid;
  v_public_route_id uuid;
  v_public_metadata jsonb;
  v_view_route_id uuid;
  v_count integer;
  v_columns_exist boolean;
BEGIN
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);

  -- (2) Compile-time check that external_id is not in the view —
  --     a select of the column raises 42703 (undefined column).
  BEGIN
    PERFORM external_id FROM public_runs LIMIT 0;
    RAISE EXCEPTION 'public_runs: external_id should not be exposed by the view';
  EXCEPTION
    WHEN undefined_column THEN NULL;
  END;

  -- (1) Insert one public + one private run for the seed user.
  -- Every owner-only metadata key the public_runs view denylists
  -- (per docs/metadata.md classification + the 20260714_001 strip
  -- additions) is included here so the assertion below can verify
  -- each one is actually scrubbed by the view. Keep this block in
  -- lockstep with the strip chain in the public_runs view migration.
  INSERT INTO runs (user_id, started_at, duration_s, distance_m, source,
                    external_id, is_public, metadata)
    VALUES (test_user, now(), 1800, 5000, 'app',
            'strava:99999990', true,
            jsonb_build_object(
              'activity_type', 'run',
              'title', 'Public test',
              'notes', 'public',
              'strava_id', '99999990',
              'garmin_id', 'test_garmin',
              'imported_from', 'strava',
              'imported_at', '2026-05-01T00:00:00Z',
              'health_connect_type', 'EXERCISE',
              'strava_activity_type', 'Run',
              'source_file', '/private/path/run.fit',
              'max_bpm', 195,
              'plan_workout_id', '00000000-0000-0000-0000-000000000123',
              'workout_step_results', jsonb_build_array(
                jsonb_build_object('step_index', 0, 'kind', 'warmup',
                                   'target_pace_sec_per_km', 360,
                                   'actual_pace_sec_per_km', 365)
              ),
              'workout_adherence', 'completed',
              'last_modified_at', '2026-05-01T00:00:00Z',
              'recovered_from_crash', true,
              'in_progress_saved_at', '2026-05-01T00:00:00Z',
              'in_progress', false,
              'manual_entry', true,
              'indoor_estimated', true,
              'distance_source', 'pedometer',
              -- 20260714_001 strip-list additions:
              'race_name', 'Richmond Half Marathon',
              'bib', 'A1234',
              'overall_place', 142,
              'chip_time', '1:47:23',
              'perceived_effort', 7,
              -- 20260724_001 strip-list addition:
              'run_number', 17
            ))
    RETURNING id INTO v_run_id;

  INSERT INTO runs (user_id, started_at, duration_s, distance_m, source,
                    is_public, metadata)
    VALUES (test_user, now(), 1800, 5000, 'app',
            false, jsonb_build_object('activity_type', 'run', 'title', 'Private'));

  -- View should only return the public run we just inserted.
  SELECT count(*) INTO v_count FROM public_runs WHERE id = v_run_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'public_runs: expected the public run to appear, got %', v_count;
  END IF;

  -- (3) (4) The metadata projection must keep public-safe keys and
  -- drop the denylisted ones.
  SELECT metadata INTO v_public_metadata FROM public_runs WHERE id = v_run_id;

  IF NOT (v_public_metadata ? 'activity_type') THEN
    RAISE EXCEPTION 'public_runs: activity_type must survive (it is public-safe)';
  END IF;
  IF NOT (v_public_metadata ? 'title') THEN
    RAISE EXCEPTION 'public_runs: title must survive (it is public-safe)';
  END IF;

  IF v_public_metadata ? 'strava_id' OR v_public_metadata ? 'garmin_id'
     OR v_public_metadata ? 'imported_from' OR v_public_metadata ? 'imported_at'
     OR v_public_metadata ? 'health_connect_type'
     OR v_public_metadata ? 'strava_activity_type'
     OR v_public_metadata ? 'source_file' OR v_public_metadata ? 'max_bpm'
     OR v_public_metadata ? 'plan_workout_id'
     OR v_public_metadata ? 'workout_step_results'
     OR v_public_metadata ? 'workout_adherence'
     OR v_public_metadata ? 'last_modified_at'
     OR v_public_metadata ? 'recovered_from_crash'
     OR v_public_metadata ? 'in_progress_saved_at'
     OR v_public_metadata ? 'in_progress'
     OR v_public_metadata ? 'manual_entry'
     OR v_public_metadata ? 'indoor_estimated'
     OR v_public_metadata ? 'distance_source'
     OR v_public_metadata ? 'race_name'
     OR v_public_metadata ? 'bib'
     OR v_public_metadata ? 'overall_place'
     OR v_public_metadata ? 'chip_time'
     OR v_public_metadata ? 'perceived_effort'
     OR v_public_metadata ? 'run_number' THEN
    RAISE EXCEPTION 'public_runs: metadata strip list incomplete — leaked at least one denylisted key';
  END IF;

  -- (5) Link the public run to a private route. View should null the
  -- link.
  INSERT INTO routes (user_id, name, distance_m, is_public, waypoints)
    VALUES (test_user, 'Private route', 1000, false, '[]'::jsonb)
    RETURNING id INTO v_private_route_id;
  UPDATE runs SET route_id = v_private_route_id WHERE id = v_run_id;

  SELECT route_id INTO v_view_route_id FROM public_runs WHERE id = v_run_id;
  IF v_view_route_id IS NOT NULL THEN
    RAISE EXCEPTION 'public_runs: route_id should be null when the joined route is private, got %', v_view_route_id;
  END IF;

  -- Flip the route to public and re-check — the link should reappear.
  INSERT INTO routes (user_id, name, distance_m, is_public, waypoints)
    VALUES (test_user, 'Public route', 1000, true, '[]'::jsonb)
    RETURNING id INTO v_public_route_id;
  UPDATE runs SET route_id = v_public_route_id WHERE id = v_run_id;

  SELECT route_id INTO v_view_route_id FROM public_runs WHERE id = v_run_id;
  IF v_view_route_id IS DISTINCT FROM v_public_route_id THEN
    RAISE EXCEPTION 'public_runs: route_id should expose the link when the joined route is public, got %', v_view_route_id;
  END IF;

  -- Cleanup. Delete in reverse FK order.
  UPDATE runs SET route_id = null WHERE id = v_run_id;
  DELETE FROM routes WHERE id IN (v_public_route_id, v_private_route_id);
  DELETE FROM runs WHERE user_id = test_user
    AND (metadata->>'title' IN ('Public test', 'Private'));
  PERFORM set_config('request.jwt.claim.role', '', true);
END $$;

-- ───────── route_reviews INSERT visibility gate (migration 20260627_001) ─────────
-- A non-existent route_id must fail the WITH CHECK, and a private
-- route owned by another user must also fail.
DO $$
DECLARE
  test_user uuid := 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';  -- runner@test.com
  other_user uuid := '99999999-9999-9999-9999-999999999991';
  v_private_route_id uuid;
  v_public_route_id uuid;
BEGIN
  -- Set up: a private route owned by another user.
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  INSERT INTO auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    VALUES (other_user, 'rls-test@example.com', '',
            now(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO routes (user_id, name, distance_m, is_public, waypoints)
    VALUES (other_user, 'private rls test route', 1000, false, '[]'::jsonb)
    RETURNING id INTO v_private_route_id;
  INSERT INTO routes (user_id, name, distance_m, is_public, waypoints)
    VALUES (other_user, 'public rls test route', 1000, true, '[]'::jsonb)
    RETURNING id INTO v_public_route_id;

  -- SET ROLE is required to exercise RLS — the seed runs as the
  -- postgres superuser by default, which bypasses RLS entirely.
  -- Switching to the `authenticated` role applies RLS as a real
  -- PostgREST request would. set_config still drives auth.uid()
  -- via the JWT-sub claim.
  PERFORM set_config('request.jwt.claim.sub', test_user::text, true);
  SET LOCAL ROLE authenticated;

  -- (The FK constraint on route_reviews.route_id already blocks
  -- truly-missing UUIDs with 23503 before the RLS gate runs, so
  -- we don't test the missing-route branch here.)

  -- Private foreign route → routes RLS returns no row → policy fails.
  BEGIN
    INSERT INTO route_reviews (route_id, user_id, rating)
      VALUES (v_private_route_id, test_user, 3);
    RAISE EXCEPTION 'route_reviews: private foreign route insert should have been blocked';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  -- Public route belonging to another user → succeeds.
  INSERT INTO route_reviews (route_id, user_id, rating)
    VALUES (v_public_route_id, test_user, 4);

  -- Cleanup. RESET ROLE so the rest of the seed runs as postgres.
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  DELETE FROM route_reviews WHERE route_id IN (v_public_route_id, v_private_route_id);
  DELETE FROM routes WHERE id IN (v_public_route_id, v_private_route_id);
  DELETE FROM auth.users WHERE id = other_user;
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
END $$;

-- ───────── routes_run_count_trigger visibility gate (migrations 20260628_001 + 20260716_001) ─────────
-- Two layered rules:
--   (1) Inserting a run that points at a route the runner cannot see
--       (private foreign route) must NOT bump that route's run_count.
--   (2) Even on a public route the runner CAN see, a private run
--       (`is_public = false`) must NOT bump the counter — that gate
--       was added in 20260716_001 to stop public_routes.run_count
--       leaking signal that someone is privately running the route.
-- A *public* run pointing at a public foreign route DOES bump.
DO $$
DECLARE
  test_user uuid := 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';  -- runner@test.com
  other_user uuid := '99999999-9999-9999-9999-999999999992';
  v_private_route_id uuid;
  v_public_route_id uuid;
  v_run_id uuid;
  v_count_priv_before int;
  v_count_priv_after int;
  v_count_pub_before int;
  v_count_pub_after int;
BEGIN
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  INSERT INTO auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    VALUES (other_user, 'run-count-test@example.com', '',
            now(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO routes (user_id, name, distance_m, is_public, waypoints)
    VALUES (other_user, 'private run-count test route', 1000, false, '[]'::jsonb)
    RETURNING id INTO v_private_route_id;
  INSERT INTO routes (user_id, name, distance_m, is_public, waypoints)
    VALUES (other_user, 'public run-count test route', 1000, true, '[]'::jsonb)
    RETURNING id INTO v_public_route_id;

  -- Baseline counts.
  SELECT run_count INTO v_count_priv_before FROM routes WHERE id = v_private_route_id;
  SELECT run_count INTO v_count_pub_before FROM routes WHERE id = v_public_route_id;

  -- Private foreign route: trigger must NOT bump.
  INSERT INTO runs (id, user_id, started_at, duration_s, distance_m, source, route_id, metadata)
    VALUES (gen_random_uuid(), test_user, now(), 600, 5000, 'app', v_private_route_id,
            jsonb_build_object('activity_type', 'run'))
    RETURNING id INTO v_run_id;
  SELECT run_count INTO v_count_priv_after FROM routes WHERE id = v_private_route_id;
  IF v_count_priv_after <> v_count_priv_before THEN
    RAISE EXCEPTION 'routes_run_count_trigger: private foreign route was inflated (% -> %)',
      v_count_priv_before, v_count_priv_after;
  END IF;
  -- Cleanup the run; DELETE must also be a no-op on the counter.
  DELETE FROM runs WHERE id = v_run_id;
  SELECT run_count INTO v_count_priv_after FROM routes WHERE id = v_private_route_id;
  IF v_count_priv_after <> v_count_priv_before THEN
    RAISE EXCEPTION 'routes_run_count_trigger: private foreign route DELETE drift (% -> %)',
      v_count_priv_before, v_count_priv_after;
  END IF;

  -- Public foreign route + private run: trigger must NOT bump
  -- (20260716_001 gate — private runs are invisible to the counter).
  INSERT INTO runs (id, user_id, started_at, duration_s, distance_m, source, route_id, metadata, is_public)
    VALUES (gen_random_uuid(), test_user, now(), 600, 5000, 'app', v_public_route_id,
            jsonb_build_object('activity_type', 'run'), false)
    RETURNING id INTO v_run_id;
  SELECT run_count INTO v_count_pub_after FROM routes WHERE id = v_public_route_id;
  IF v_count_pub_after <> v_count_pub_before THEN
    RAISE EXCEPTION 'routes_run_count_trigger: private run on public foreign route should NOT bump (% -> %)',
      v_count_pub_before, v_count_pub_after;
  END IF;
  DELETE FROM runs WHERE id = v_run_id;

  -- Public foreign route + public run: trigger MUST bump.
  INSERT INTO runs (id, user_id, started_at, duration_s, distance_m, source, route_id, metadata, is_public)
    VALUES (gen_random_uuid(), test_user, now(), 600, 5000, 'app', v_public_route_id,
            jsonb_build_object('activity_type', 'run'), true)
    RETURNING id INTO v_run_id;
  SELECT run_count INTO v_count_pub_after FROM routes WHERE id = v_public_route_id;
  IF v_count_pub_after <> v_count_pub_before + 1 THEN
    RAISE EXCEPTION 'routes_run_count_trigger: public run on public foreign route should bump by 1 (% -> %)',
      v_count_pub_before, v_count_pub_after;
  END IF;
  -- And DELETE decrements it back.
  DELETE FROM runs WHERE id = v_run_id;
  SELECT run_count INTO v_count_pub_after FROM routes WHERE id = v_public_route_id;
  IF v_count_pub_after <> v_count_pub_before THEN
    RAISE EXCEPTION 'routes_run_count_trigger: public foreign route DELETE should restore (% -> %)',
      v_count_pub_before, v_count_pub_after;
  END IF;

  -- Cleanup.
  DELETE FROM routes WHERE id IN (v_public_route_id, v_private_route_id);
  DELETE FROM auth.users WHERE id = other_user;
  PERFORM set_config('request.jwt.claim.role', '', true);
END $$;

-- ───────── event_attendees self-RSVP visibility gate (migration 20260629_001) ─────────
-- Self-RSVP must be gated on event visibility — an authenticated
-- user can no longer plant attendee rows against private-club
-- events they enumerated UUIDs for.
DO $$
DECLARE
  test_user uuid := 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';  -- runner@test.com
  other_user uuid := '99999999-9999-9999-9999-999999999993';
  v_private_club_id uuid;
  v_public_club_id uuid;
  v_private_event_id uuid;
  v_public_event_id uuid;
  v_instance timestamptz := '2099-01-01T10:00:00+00';
BEGIN
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  INSERT INTO auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    VALUES (other_user, 'rsvp-rls-test@example.com', '',
            now(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO clubs (name, slug, owner_id, is_public)
    VALUES ('rsvp-rls private', 'rsvp-rls-private-' || floor(random()*1e6), other_user, false)
    RETURNING id INTO v_private_club_id;
  INSERT INTO clubs (name, slug, owner_id, is_public)
    VALUES ('rsvp-rls public', 'rsvp-rls-public-' || floor(random()*1e6), other_user, true)
    RETURNING id INTO v_public_club_id;
  INSERT INTO events (club_id, title, starts_at, created_by)
    VALUES (v_private_club_id, 'private event', v_instance, other_user)
    RETURNING id INTO v_private_event_id;
  INSERT INTO events (club_id, title, starts_at, created_by)
    VALUES (v_public_club_id, 'public event', v_instance, other_user)
    RETURNING id INTO v_public_event_id;

  -- Apply RLS as the test user.
  PERFORM set_config('request.jwt.claim.sub', test_user::text, true);
  SET LOCAL ROLE authenticated;

  -- Self-RSVP on a private-club event the user can't see → blocked.
  BEGIN
    INSERT INTO event_attendees (event_id, user_id, instance_start, status)
      VALUES (v_private_event_id, test_user, v_instance, 'going');
    RAISE EXCEPTION 'event_attendees: self-RSVP to private-club event should have been blocked';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  -- Self-RSVP on a public-club event → succeeds.
  INSERT INTO event_attendees (event_id, user_id, instance_start, status)
    VALUES (v_public_event_id, test_user, v_instance, 'going');

  -- Cleanup.
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  DELETE FROM event_attendees WHERE event_id IN (v_public_event_id, v_private_event_id);
  DELETE FROM events WHERE id IN (v_public_event_id, v_private_event_id);
  DELETE FROM clubs WHERE id IN (v_public_club_id, v_private_club_id);
  DELETE FROM auth.users WHERE id = other_user;
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
END $$;

-- ───────── RLS audit cleanup batch (migration 20260630_001) ─────────
-- (a) fitness_snapshots client-INSERT must reject `source='server'`.
-- (b) authenticated must NOT be able to INSERT/UPDATE/DELETE
--     personal_records or monthly_funding (RLS + GRANTs both deny).
DO $$
DECLARE
  test_user uuid := 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';  -- runner@test.com
BEGIN
  PERFORM set_config('request.jwt.claim.sub', test_user::text, true);
  SET LOCAL ROLE authenticated;

  -- (a) fitness_snapshots: source='client' allowed, source='server' blocked.
  INSERT INTO fitness_snapshots (user_id, vdot, source)
    VALUES (test_user, 50.0, 'client');
  BEGIN
    INSERT INTO fitness_snapshots (user_id, vdot, source)
      VALUES (test_user, 99.9, 'server');
    RAISE EXCEPTION 'fitness_snapshots: source=server insert should have been blocked';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  -- (b) personal_records: writes must be blocked.
  BEGIN
    INSERT INTO personal_records (user_id, distance, best_time_s, run_id, achieved_at)
      VALUES (test_user, '5k', 1, '00000000-0000-0000-0000-000000000000', now());
    RAISE EXCEPTION 'personal_records: client INSERT should have been blocked';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
    WHEN check_violation THEN NULL;
  END;

  -- (b) monthly_funding: writes must be blocked.
  BEGIN
    INSERT INTO monthly_funding (month, amount_received)
      VALUES ('2099-01-01', 9999.99);
    RAISE EXCEPTION 'monthly_funding: client INSERT should have been blocked';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  -- Cleanup the legitimate fitness_snapshots row we inserted.
  RESET ROLE;
  DELETE FROM fitness_snapshots WHERE user_id = test_user AND vdot = 50.0;
  PERFORM set_config('request.jwt.claim.sub', '', true);
END $$;

-- ───────── runs public-anyone policy drop (migration 20260701_001) ─────────
-- The wire-leak closer. After this migration:
--   * Direct `from runs` SELECT for non-owner rows returns zero
--     (only `users own their runs` policy remains).
--   * The public_runs view still serves rows (view runs as owner).
--   * Sibling tables (run_kudos, run_comments, run_photos,
--     segment_efforts, live_run_pings) still surface their rows on
--     public runs to non-owners via is_run_visible_to.
DO $$
DECLARE
  test_user uuid := 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';  -- runner@test.com
  other_user uuid := '99999999-9999-9999-9999-999999999994';
  v_public_run_id uuid;
  v_private_run_id uuid;
  v_kudo_count int;
  v_comment_id uuid;
  v_runs_visible int;
  v_view_visible int;
BEGIN
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  INSERT INTO auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    VALUES (other_user, 'wire-leak-test@example.com', '',
            now(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated')
    ON CONFLICT (id) DO NOTHING;

  -- A public run and a private run, both owned by `other_user`.
  INSERT INTO runs (id, user_id, started_at, duration_s, distance_m,
                    source, is_public, metadata)
    VALUES (gen_random_uuid(), other_user, now(), 600, 5000, 'app', true,
            jsonb_build_object('activity_type', 'run'))
    RETURNING id INTO v_public_run_id;
  INSERT INTO runs (id, user_id, started_at, duration_s, distance_m,
                    source, is_public, metadata)
    VALUES (gen_random_uuid(), other_user, now(), 600, 5000, 'app', false,
            jsonb_build_object('activity_type', 'run'))
    RETURNING id INTO v_private_run_id;

  -- Plant a kudo on the public run by `other_user`. We expect
  -- `test_user` (a non-owner) to see this kudo via the helper.
  INSERT INTO run_kudos (run_id, user_id) VALUES (v_public_run_id, other_user);
  -- And a comment.
  INSERT INTO run_comments (run_id, author_id, body)
    VALUES (v_public_run_id, other_user, 'great run')
    RETURNING id INTO v_comment_id;

  -- Apply RLS as the test_user (a non-owner of these runs).
  PERFORM set_config('request.jwt.claim.sub', test_user::text, true);
  SET LOCAL ROLE authenticated;

  -- (a) Direct `runs` SELECT for the public row must return zero
  -- (this is the wire-leak closing).
  SELECT count(*) INTO v_runs_visible
    FROM runs WHERE id = v_public_run_id;
  IF v_runs_visible <> 0 THEN
    RAISE EXCEPTION 'runs base table still leaks public rows to non-owners (got %)',
      v_runs_visible;
  END IF;
  -- And the private row stays hidden too.
  SELECT count(*) INTO v_runs_visible
    FROM runs WHERE id = v_private_run_id;
  IF v_runs_visible <> 0 THEN
    RAISE EXCEPTION 'runs base table leaks private rows to non-owners (got %)',
      v_runs_visible;
  END IF;

  -- (b) The public_runs view still serves the public row.
  SELECT count(*) INTO v_view_visible
    FROM public_runs WHERE id = v_public_run_id;
  IF v_view_visible <> 1 THEN
    RAISE EXCEPTION 'public_runs view should still serve public rows (got %)',
      v_view_visible;
  END IF;
  -- And it does NOT serve the private row.
  SELECT count(*) INTO v_view_visible
    FROM public_runs WHERE id = v_private_run_id;
  IF v_view_visible <> 0 THEN
    RAISE EXCEPTION 'public_runs view leaks private rows (got %)', v_view_visible;
  END IF;

  -- (c) Sibling tables: kudos / comments on the PUBLIC run must
  -- still be visible to test_user via is_run_visible_to.
  SELECT count(*) INTO v_kudo_count
    FROM run_kudos WHERE run_id = v_public_run_id;
  IF v_kudo_count <> 1 THEN
    RAISE EXCEPTION 'run_kudos on public run should be visible to non-owners (got %)',
      v_kudo_count;
  END IF;
  SELECT count(*) INTO v_kudo_count
    FROM run_comments WHERE run_id = v_public_run_id;
  IF v_kudo_count <> 1 THEN
    RAISE EXCEPTION 'run_comments on public run should be visible to non-owners (got %)',
      v_kudo_count;
  END IF;

  -- (d) Sibling tables: kudos / comments on the PRIVATE run must
  -- NOT be visible.
  -- Plant private-run engagement first (need to switch back to
  -- service-role briefly).
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  INSERT INTO run_kudos (run_id, user_id) VALUES (v_private_run_id, other_user);
  PERFORM set_config('request.jwt.claim.sub', test_user::text, true);
  SET LOCAL ROLE authenticated;

  SELECT count(*) INTO v_kudo_count
    FROM run_kudos WHERE run_id = v_private_run_id;
  IF v_kudo_count <> 0 THEN
    RAISE EXCEPTION 'run_kudos on private run should be invisible to non-owners (got %)',
      v_kudo_count;
  END IF;

  -- Cleanup. Clear claim.sub first — the runs DELETE fires the
  -- personal_records trigger which calls refresh_personal_records_for_user;
  -- its caller-identity guard (20260515_001) raises if auth.uid()
  -- (= test_user from claim.sub) doesn't match the target row's
  -- user_id (= other_user). Clearing sub leaves auth.uid() null,
  -- which the guard explicitly skips.
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  DELETE FROM run_kudos WHERE run_id IN (v_public_run_id, v_private_run_id);
  DELETE FROM run_comments WHERE run_id IN (v_public_run_id, v_private_run_id);
  DELETE FROM runs WHERE id IN (v_public_run_id, v_private_run_id);
  DELETE FROM auth.users WHERE id = other_user;
  PERFORM set_config('request.jwt.claim.role', '', true);
END $$;
