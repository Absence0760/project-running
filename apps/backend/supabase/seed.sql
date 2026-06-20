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
-- age_confirmed_at + terms_accepted_at stamped at seed time so the
-- seed user represents the post-confirm-age-and-terms state (the
-- realistic shape every signup produces). See migration
-- 20260929_001 + audit/gdpr (2026-05-25).
-- `onboarded_at` is stamped so the seed user is treated as already
-- past the post-signup wizard (migration `20261016_001` adds the
-- column; the migration's backfill only runs once on db reset, but
-- seed.sql then inserts fresh rows that would otherwise land with
-- onboarded_at=null + get caught by the layout-level routing gate
-- — every Playwright spec using the seeded user would then be
-- redirected to /onboarding instead of its actual route).
-- `height_cm`, `date_of_birth`, `gender` feed the Mifflin-St Jeor BMR on
-- /nutrition (get_my_profile() returns the whole row). Without them the macro
-- rings render in their untargeted "set your body metrics" state.
INSERT INTO user_profiles (id, display_name, parkrun_number, preferred_unit, subscription_tier,
                           age_confirmed_at, terms_accepted_at, onboarded_at,
                           height_cm, date_of_birth, gender)
VALUES ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Jared Howard', 'A123456', 'km', 'free',
        now(), now(), now(),
        178.0, '1992-09-12', 'male')
ON CONFLICT (id) DO NOTHING;

-- Make the seed user an admin so /admin/reports is testable locally.
INSERT INTO app_admins (user_id)
VALUES ('a1b2c3d4-e5f6-7890-abcd-ef1234567890')
ON CONFLICT (user_id) DO NOTHING;

-- 2a. User settings — runner_context for the AI Coach. Without these the
-- coach has nothing to ground HR / age / weekly-goal answers in. Keys
-- match `docs/backend/settings.md` § Universal prefs registry.
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
    'week_start_day', 'monday',
    -- Activity / goal drive the /nutrition macro targets (TDEE multiplier
    -- + lose/maintain/gain calorie delta).
    'nutrition_activity_level', 'active',
    'nutrition_goal', 'maintain'
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
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Belle Isle + Pipeline Loop',
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
-- `route_id` links each run to the public route it was run on (resolved
-- by name, unique per user) so /routes/[id]'s "past efforts" panel and
-- the run↔route association are real, not orphaned.
INSERT INTO runs (id, user_id, started_at, duration_s, distance_m, source, is_public, route_id, track_url, metadata) VALUES
  -- Belle Isle + Pipeline Loop tempo run, Richmond
  ('a1000001-0000-0000-0000-000000000001'::uuid,
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    '2026-05-15 07:30:00+00', 2280, 6500.0, 'app', true,
    (SELECT id FROM routes WHERE user_id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890' AND name = 'Belle Isle + Pipeline Loop' LIMIT 1),
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890/a1000001-0000-0000-0000-000000000001.json.gz',
    '{"activity_type":"run","title":"Tempo on Belle Isle","avg_bpm":158,"steps":7900}'::jsonb),
  -- UVA Rotunda Loop easy run, Charlottesville
  ('a1000001-0000-0000-0000-000000000002'::uuid,
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    '2026-05-12 18:00:00+00', 1620, 4200.0, 'app', true,
    (SELECT id FROM routes WHERE user_id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890' AND name = 'UVA Rotunda Loop (Charlottesville)' LIMIT 1),
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890/a1000001-0000-0000-0000-000000000002.json.gz',
    '{"activity_type":"run","title":"UVA loop after work","avg_bpm":146,"steps":5400}'::jsonb),
  -- Mount Vernon Trail long run, Arlington
  ('a1000001-0000-0000-0000-000000000003'::uuid,
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    '2026-05-10 06:45:00+00', 3720, 10200.0, 'app', false,
    (SELECT id FROM routes WHERE user_id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890' AND name = 'Mount Vernon Trail North (Arlington)' LIMIT 1),
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890/a1000001-0000-0000-0000-000000000003.json.gz',
    '{"activity_type":"run","title":"Sunday long along the Potomac","avg_bpm":152,"steps":12800}'::jsonb),
  -- Mill Mountain Star Climb hill workout, Roanoke
  ('a1000001-0000-0000-0000-000000000004'::uuid,
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    '2026-05-08 08:00:00+00', 2580, 7200.0, 'app', true,
    (SELECT id FROM routes WHERE user_id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890' AND name = 'Mill Mountain Star Climb (Roanoke)' LIMIT 1),
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890/a1000001-0000-0000-0000-000000000004.json.gz',
    '{"activity_type":"run","title":"Star climb hill reps","avg_bpm":165,"steps":8800}'::jsonb);

-- More run history built from the SAME real public routes that show up
-- on the heatmap + Explore tab. Two are first efforts on the public
-- routes that previously had none (Norfolk Botanical Garden, VA Beach
-- Boardwalk); the other four are repeat efforts on routes that already
-- have a run, so /routes/[id] gets a populated "past efforts on this
-- route" panel and the dashboard has a fuller week. Unlike the four
-- rows above, these set `route_id` (resolved by name — unique per
-- user) so the run↔route link the route-detail history reads is real.
-- Tracks are uploaded by scripts/seed-run-tracks.mjs (matching UUIDs);
-- until `npm run dev:db:seed-tracks` runs they show "No GPS track".
INSERT INTO runs (id, user_id, started_at, duration_s, distance_m, source, is_public, route_id, track_url, metadata) VALUES
  -- Norfolk Botanical Garden Loop — first effort on this public route
  ('a1000001-0000-0000-0000-000000000005'::uuid,
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    '2026-05-22 07:15:00+00', 1680, 4800.0, 'app', true,
    (SELECT id FROM routes WHERE user_id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890' AND name = 'Norfolk Botanical Garden Loop' LIMIT 1),
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890/a1000001-0000-0000-0000-000000000005.json.gz',
    '{"activity_type":"run","title":"Botanical Garden shakeout","avg_bpm":148,"steps":6100}'::jsonb),
  -- VA Beach Boardwalk Out & Back — first effort on this public route
  ('a1000001-0000-0000-0000-000000000006'::uuid,
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    '2026-05-19 06:50:00+00', 1980, 6300.0, 'app', true,
    (SELECT id FROM routes WHERE user_id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890' AND name = 'VA Beach Boardwalk Out & Back' LIMIT 1),
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890/a1000001-0000-0000-0000-000000000006.json.gz',
    '{"activity_type":"run","title":"Boardwalk sunrise miles","avg_bpm":150,"steps":7700}'::jsonb),
  -- Belle Isle + Pipeline Loop — repeat tempo (faster than the 05-15 one)
  ('a1000001-0000-0000-0000-000000000007'::uuid,
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    '2026-05-29 07:20:00+00', 2160, 6500.0, 'app', true,
    (SELECT id FROM routes WHERE user_id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890' AND name = 'Belle Isle + Pipeline Loop' LIMIT 1),
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890/a1000001-0000-0000-0000-000000000007.json.gz',
    '{"activity_type":"run","title":"Belle Isle tempo (repeat)","avg_bpm":161,"steps":7850}'::jsonb),
  -- UVA Rotunda Loop — repeat easy evening run
  ('a1000001-0000-0000-0000-000000000008'::uuid,
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    '2026-05-25 18:10:00+00', 1560, 4200.0, 'app', true,
    (SELECT id FROM routes WHERE user_id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890' AND name = 'UVA Rotunda Loop (Charlottesville)' LIMIT 1),
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890/a1000001-0000-0000-0000-000000000008.json.gz',
    '{"activity_type":"run","title":"Evening UVA loop","avg_bpm":145,"steps":5300}'::jsonb),
  -- Mount Vernon Trail North — repeat long run (kept private like the first)
  ('a1000001-0000-0000-0000-000000000009'::uuid,
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    '2026-05-24 06:40:00+00', 3540, 10200.0, 'app', false,
    (SELECT id FROM routes WHERE user_id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890' AND name = 'Mount Vernon Trail North (Arlington)' LIMIT 1),
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890/a1000001-0000-0000-0000-000000000009.json.gz',
    '{"activity_type":"run","title":"Potomac long run","avg_bpm":150,"steps":12700}'::jsonb),
  -- Mill Mountain Star Climb — repeat hill session
  ('a1000001-0000-0000-0000-00000000000a'::uuid,
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    '2026-05-17 08:10:00+00', 2640, 7200.0, 'app', true,
    (SELECT id FROM routes WHERE user_id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890' AND name = 'Mill Mountain Star Climb (Roanoke)' LIMIT 1),
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890/a1000001-0000-0000-0000-00000000000a.json.gz',
    '{"activity_type":"run","title":"Mill Mountain hill reps","avg_bpm":166,"steps":8950}'::jsonb);

-- Bulk repeat efforts on the real routes so /runs/heatmap shows genuine
-- density (frequently-run routes accumulate heat; the high-zoom line
-- layer gets overlapping paths to reveal). is_public = false on purpose:
-- they feed the runner's OWN personal heatmap + dashboard without
-- flooding the public activity feed or the community /routes/heatmap
-- (which reads public routes, not runs). The UUIDs + per-route counts
-- here MUST match the REPEAT_SPEC generator in
-- scripts/seed-run-tracks.mjs, which uploads the matching tracks; run
-- `npm run dev:db:seed-tracks` after `supabase db reset`.
INSERT INTO runs (id, user_id, started_at, duration_s, distance_m, source, is_public, route_id, track_url, metadata)
SELECT
  ('a1000002-0000-0000-0000-' || lpad((s.idx * 100 + j)::text, 12, '0'))::uuid,
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890'::uuid,
  TIMESTAMPTZ '2026-05-26 07:30:00+00' - (j * interval '7 days') - (s.idx * interval '1 day'),
  s.base_dur + (j % 5) * 30,
  s.dist,
  'app',
  false,
  (SELECT id FROM routes r
     WHERE r.user_id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890' AND r.name = s.name
     LIMIT 1),
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890/a1000002-0000-0000-0000-'
    || lpad((s.idx * 100 + j)::text, 12, '0') || '.json.gz',
  jsonb_build_object(
    'activity_type', 'run',
    'title', s.name || ' #' || j::text,
    'avg_bpm', s.bpm,
    'steps', s.steps
  )
FROM (VALUES
  (0, 'Belle Isle + Pipeline Loop',            6500,  2200, 16, 158,  7900),
  (1, 'UVA Rotunda Loop (Charlottesville)',    4200,  1560,  6, 146,  5400),
  (2, 'Mount Vernon Trail North (Arlington)', 10200,  3600,  5, 152, 12800),
  (3, 'Mill Mountain Star Climb (Roanoke)',    7200,  2580,  4, 165,  8800),
  (4, 'Norfolk Botanical Garden Loop',         4800,  1680,  5, 148,  6100),
  (5, 'VA Beach Boardwalk Out & Back',         6300,  1980,  4, 150,  7700)
) AS s(idx, name, dist, base_dur, repeats, bpm, steps),
LATERAL generate_series(1, s.repeats) AS j;

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
    'Belle Isle + Pipeline Loop',
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

-- The activity_type column was promoted out of the metadata bag (migration
-- 20261207_001), but these INSERTs still carry the type in metadata only, so
-- the real column defaults to 'run' for every row. Backfill it from metadata
-- where they differ — otherwise the walk + hike seed rows read as plain runs
-- and the History / runs activity-type filters (Walk / Hike / …) match nothing.
UPDATE runs SET activity_type = metadata->>'activity_type'
  WHERE metadata ? 'activity_type'
    AND metadata->>'activity_type' <> activity_type
    AND metadata->>'activity_type' IN ('run', 'walk', 'hike', 'cycle', 'stroller');

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

-- All three clubs are Virginia-themed so the seed reads consistently
-- with the heatmap-tab Virginia tile extract + the six VA clubs +
-- the discoverable_routes_in_bbox / clubs_in_bbox RPCs (migration
-- 20260911_001). location_point on the two public clubs is set in
-- the UPDATEs below — the column isn't part of the INSERT shape
-- because PostGIS geography literals don't round-trip through the
-- positional VALUES clause cleanly here.
INSERT INTO clubs (id, owner_id, name, slug, description, location_label, is_public, join_policy, invite_token)
VALUES
  ('c1111111-0000-0000-0000-000000000001',
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
   'Richmond Run Club',
   'richmond-run-club',
   'Weekly long runs from Belle Isle. All paces, all welcome.',
   'Richmond, VA',
   true, 'open', null),
  ('c2222222-0000-0000-0000-000000000002',
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
   'UVA Tempo Tuesday',
   'tempo-tuesday',
   'Weekly threshold session in Charlottesville. Request to join — group around 15.',
   'Charlottesville, VA',
   true, 'request', null),
  ('c3333333-0000-0000-0000-000000000003',
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
   'Friends of Jared',
   'friends-of-jared',
   'Small private group for pre-race meetups and trip planning.',
   'Richmond, VA',
   false, 'invite',
   'c3fr13nd50fj4r3dc1ubtoken000000');

-- Pin the two public clubs to their stated cities so the heatmap-tab
-- discoverable-pin layer (clubs_in_bbox + discoverable_routes_in_bbox,
-- migration 20260911_001) lights up. friends-of-jared keeps a NULL
-- location_point — private clubs aren't on the discoverable map.
UPDATE clubs SET location_point = ST_GeogFromText('SRID=4326;POINT(-77.4360 37.5407)')
  WHERE id = 'c1111111-0000-0000-0000-000000000001'::uuid;
UPDATE clubs SET location_point = ST_GeogFromText('SRID=4326;POINT(-78.4767 38.0293)')
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
UPDATE routes SET is_featured = true, featured_at = now()
  WHERE name IN (
    'Belle Isle + Pipeline Loop',
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

-- onboarded_at: same reason as the runner profile above.
INSERT INTO user_profiles (id, display_name, preferred_unit, subscription_tier,
                           age_confirmed_at, terms_accepted_at, onboarded_at)
VALUES ('b2c3d4e5-f6a7-8901-bcde-f23456789012', 'Alex Chen', 'km', 'free',
        now(), now(), now())
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
  recurrence_freq, recurrence_byday, author_id
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

-- ───────── Cross-club activity discovery (the /social Discover tab) ─────────
-- Backs search_public_events (migrations 20270110_001 + 20270111_001). The
-- three events above are all category='run', free, untyped — they don't
-- exercise the discovery filters. This block fans events across the public
-- Virginia clubs so EVERY Discover filter dimension has something to match:
--   * category   — run / cycle / class / social (≥1 each)
--   * cadence    — one_off / weekly / biweekly / monthly (≥1 each)
--   * weekday    — MO/TU/WE/TH/FR/SA/SU spread (byday + one-off isodow)
--   * time       — morning (05–11) / afternoon (12–16) / evening (17–04)
--   * paid/free  — three priced events + the rest free
--   * discipline — Yoga / Pilates / Spin / Gravel / Strength text search
--
-- Times are anchored to America/New_York (EDT = UTC−4 in June) so the
-- timezone-aware time-of-day bucket resolves to the organiser's intended
-- LOCAL hour, not the UTC instant (e.g. 23:00Z = 19:00 EDT → evening). The
-- recurring anchors use a near-future date whose weekday matches byday for
-- readability; the one-offs sit in the next two weeks so they pass the
-- `starts_at >= now()` upcoming gate.
INSERT INTO events (
  id, club_id, title, description, starts_at, timezone, duration_min, meet_label,
  category, discipline, capacity, recurrence_freq, recurrence_byday, author_id
) VALUES
  -- run · weekly · SA · morning (07:00 EDT) · free
  ('e4444444-0000-0000-0000-0000000000d1',
   'c1111111-0000-0000-0000-000000000001',
   'Saturday Sunrise 5K',
   'Easy social 5K from Belle Isle at first light. Coffee at the lot after.',
   '2026-06-13T11:00:00Z', 'America/New_York', 45, 'Belle Isle parking lot',
   'run', null, null, 'weekly', ARRAY['SA'],
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890'),
  -- cycle · weekly · WE · afternoon (14:00 EDT) · free · discipline "Gravel Ride"
  ('e5555555-0000-0000-0000-0000000000d2',
   'c4444444-0000-0000-0000-000000000004',
   'Wednesday Gravel Ride',
   'Rolling gravel along the W&OD. ~40 km, regroup at every turn.',
   '2026-06-17T18:00:00Z', 'America/New_York', 150, 'Memorial Bridge',
   'cycle', 'Gravel Ride', 25, 'weekly', ARRAY['WE'],
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890'),
  -- class · weekly · TH · evening (19:00 EDT) · free · discipline "Vinyasa Yoga"
  ('e6666666-0000-0000-0000-0000000000d3',
   'c5555555-0000-0000-0000-000000000005',
   'Recovery Vinyasa',
   'Gentle flow for runners. Mats provided; first class free.',
   '2026-06-18T23:00:00Z', 'America/New_York', 60, 'Botanical Garden studio',
   'class', 'Vinyasa Yoga', 16, 'weekly', ARRAY['TH'],
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890'),
  -- social · biweekly · FR · evening (18:30 EDT) · free · discipline "Post-run Social"
  ('e7777777-0000-0000-0000-0000000000d4',
   'c9999999-0000-0000-0000-000000000009',
   'Trailhead Social',
   'Post-run hang at the brewery. No pace, no pressure — bring a friend.',
   '2026-06-19T22:30:00Z', 'America/New_York', 90, 'Three Notch''d Brewing',
   'social', 'Post-run Social', null, 'biweekly', ARRAY['FR'],
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890'),
  -- run · monthly · SU · morning (06:30 EDT) · free
  ('e8888888-0000-0000-0000-0000000000d5',
   'c8888888-0000-0000-0000-000000000008',
   'Monthly Marathon Long Run',
   'Progressive long run on the marathon course. Aid every 5 km.',
   '2026-06-14T10:30:00Z', 'America/New_York', 180, 'Belle Isle parking lot',
   'run', null, null, 'monthly', ARRAY['SU'],
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890'),
  -- run · ONE-OFF (future SA) · morning (08:00 EDT) · free
  ('e9999999-0000-0000-0000-0000000000d6',
   'c6666666-0000-0000-0000-000000000006',
   'Boardwalk 10K Time Trial',
   'Flat-and-fast 10K time trial on the Boardwalk. Chip-free, run your own.',
   '2026-06-20T12:00:00Z', 'America/New_York', 60, 'VA Beach Boardwalk, 17th St',
   'run', null, 100, null, null,
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890'),
  -- class · weekly · MO · evening (18:00 EDT) · PAID · discipline "Reformer Pilates"
  ('ea000000-0000-0000-0000-0000000000d7',
   'c5555555-0000-0000-0000-000000000005',
   'Reformer Pilates',
   'Reformer core + mobility for runners. Six machines — booking required.',
   '2026-06-15T22:00:00Z', 'America/New_York', 50, 'Botanical Garden studio',
   'class', 'Reformer Pilates', 6, 'weekly', ARRAY['MO'],
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890'),
  -- cycle · biweekly · TU · afternoon (12:00 EDT) · PAID · discipline "Spin"
  ('eb000000-0000-0000-0000-0000000000d8',
   'c4444444-0000-0000-0000-000000000004',
   'Indoor Spin Studio',
   'Lunchtime 45-min spin intervals. Shoes + towel provided.',
   '2026-06-16T16:00:00Z', 'America/New_York', 45, 'Crystal City studio',
   'cycle', 'Spin', 20, 'biweekly', ARRAY['TU'],
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890'),
  -- class · ONE-OFF (future SA) · morning (10:00 EDT) · PAID · discipline "Strength & Mobility"
  ('ec000000-0000-0000-0000-0000000000d9',
   'c7777777-0000-0000-0000-000000000007',
   'Strength for Runners Workshop',
   'Two-hour strength + mobility workshop. Kettlebells supplied; bring water.',
   '2026-06-27T14:00:00Z', 'America/New_York', 120, 'Mill Mountain rec centre',
   'class', 'Strength & Mobility', 18, null, null,
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890');

-- Price the three paid discovery events. event_pricing has a BEFORE-INSERT
-- trigger gating pricing on the host's charges_enabled Stripe capability;
-- the seed has no Stripe Connect account, so bypass it the same way the
-- search_public_events pgtap fixture does (session_replication_role=replica
-- suspends triggers for this superuser session only). NULL instance_start =
-- the series default price the discovery "from" collapses to.
SET session_replication_role = replica;
INSERT INTO event_pricing (event_id, price_cents, currency) VALUES
  ('ea000000-0000-0000-0000-0000000000d7', 1800, 'usd'),
  ('eb000000-0000-0000-0000-0000000000d8', 1200, 'usd'),
  ('ec000000-0000-0000-0000-0000000000d9', 2500, 'usd');
SET session_replication_role = origin;

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
  'Richmond Half 2026',
  'distance_half', 21097.5, 5700,    -- 1:35:00 target
  '2026-03-29', '2026-06-20', 5, 52.0, 1320,   -- 22:00 recent 5K
  'active', 'manual',
  '["80% of weekly mileage should be easy","Never increase weekly volume more than 10% week-over-week","Long run is non-negotiable — protect Sunday","Sleep 8 hours through build weeks"]'::jsonb,
  'Goal race: Richmond Half Marathon, 2026-06-21.'
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

-- onboarded_at: same reason as the runner profile above.
INSERT INTO user_profiles (id, display_name, preferred_unit, subscription_tier,
                           age_confirmed_at, terms_accepted_at, onboarded_at)
VALUES ('c3d4e5f6-a7b8-9012-cdef-345678901234', 'Morgan Lee', 'km', 'free',
        now(), now(), now())
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

-- ───────────────── Discovery scenario testbed (Denver) ─────────────────
--
-- A dense cluster of public routes around Denver, CO — deliberately
-- far from the Virginia demo routes (so the VA-based e2e counts are
-- untouched) — built to exercise every route-discovery edge case the
-- map browser has to handle:
--
--   Group A — three routes share the EXACT same start point
--             (Wash Park, 39.7400/-105.0000): overlapping start dots
--             must collapse into one cluster bubble.
--   Group B — three routes share the EXACT same end point
--             (Confluence, 39.7600/-105.0200): the hover-preview lines
--             converge even though the start dots are spread out.
--   Group C — three routes start within ~30 m of each other (City
--             Park): cluster at city zoom, separate when you zoom in.
--   Group D — three loop variations share BOTH start and end
--             (Sloan Lake, 39.7300/-105.0550): every endpoint overlaps.
--   Group E — a marathon + an ultra so the distance-band filter has
--             long-distance data here too.
--   Group F — one route owned by alex (a runner-followee) so the
--             `friends` lens lights up in this area.
--
-- Distances are spread across the 5K/10K/Half/Marathon/Ultra bands and
-- the lens states (featured / run_count>0 / un-run hidden gem) are set
-- by the UPDATEs below, so every filter permutation returns something.
INSERT INTO routes (user_id, name, waypoints, distance_m, elevation_m, surface, is_public) VALUES
-- Group A: identical start (39.7400, -105.0000)
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Wash Park 5K Loop',
  '[{"lat":39.7400,"lng":-105.0000,"ele":1600},{"lat":39.7410,"lng":-104.9980,"ele":1602},{"lat":39.7420,"lng":-105.0000,"ele":1605},{"lat":39.7410,"lng":-105.0020,"ele":1603},{"lat":39.7400,"lng":-105.0000,"ele":1600}]',
  5000, 20, 'road', true),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Wash Park 10K Spur',
  '[{"lat":39.7400,"lng":-105.0000,"ele":1600},{"lat":39.7440,"lng":-105.0050,"ele":1610},{"lat":39.7460,"lng":-105.0080,"ele":1618},{"lat":39.7480,"lng":-105.0100,"ele":1625}]',
  10000, 40, 'road', true),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Wash Park Half Adventure',
  '[{"lat":39.7400,"lng":-105.0000,"ele":1600},{"lat":39.7500,"lng":-105.0100,"ele":1640},{"lat":39.7600,"lng":-105.0200,"ele":1680},{"lat":39.7700,"lng":-105.0300,"ele":1720}]',
  21000, 130, 'trail', true),
-- Group B: identical end (39.7600, -105.0200)
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Cherry Creek to Confluence',
  '[{"lat":39.7400,"lng":-105.0500,"ele":1590},{"lat":39.7480,"lng":-105.0380,"ele":1600},{"lat":39.7550,"lng":-105.0280,"ele":1610},{"lat":39.7600,"lng":-105.0200,"ele":1615}]',
  4800, 25, 'road', true),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Highline Canal Finish',
  '[{"lat":39.7700,"lng":-105.0400,"ele":1620},{"lat":39.7660,"lng":-105.0320,"ele":1618},{"lat":39.7620,"lng":-105.0250,"ele":1616},{"lat":39.7600,"lng":-105.0200,"ele":1615}]',
  9500, 35, 'trail', true),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'City Park Sprint to Confluence',
  '[{"lat":39.7450,"lng":-105.0300,"ele":1605},{"lat":39.7520,"lng":-105.0250,"ele":1610},{"lat":39.7570,"lng":-105.0220,"ele":1613},{"lat":39.7600,"lng":-105.0200,"ele":1615}]',
  5500, 18, 'road', true),
-- Group C: close (~30 m apart) starts near (39.7445, -104.9500)
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'City Park North',
  '[{"lat":39.7445,"lng":-104.9500,"ele":1580},{"lat":39.7470,"lng":-104.9450,"ele":1585},{"lat":39.7460,"lng":-104.9400,"ele":1588}]',
  5800, 22, 'road', true),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'City Park East',
  '[{"lat":39.7447,"lng":-104.9498,"ele":1580},{"lat":39.7480,"lng":-104.9460,"ele":1586},{"lat":39.7500,"lng":-104.9420,"ele":1590}]',
  10000, 30, 'mixed', true),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'City Park South',
  '[{"lat":39.7443,"lng":-104.9502,"ele":1580},{"lat":39.7420,"lng":-104.9460,"ele":1584},{"lat":39.7400,"lng":-104.9420,"ele":1588}]',
  15000, 60, 'trail', true),
-- Group D: shared start AND end loops (39.7300, -105.0550)
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Sloan Lake Loop CW',
  '[{"lat":39.7300,"lng":-105.0550,"ele":1610},{"lat":39.7330,"lng":-105.0520,"ele":1612},{"lat":39.7340,"lng":-105.0560,"ele":1614},{"lat":39.7320,"lng":-105.0580,"ele":1612},{"lat":39.7300,"lng":-105.0550,"ele":1610}]',
  5000, 15, 'road', true),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Sloan Lake Loop CCW',
  '[{"lat":39.7300,"lng":-105.0550,"ele":1610},{"lat":39.7320,"lng":-105.0580,"ele":1612},{"lat":39.7340,"lng":-105.0560,"ele":1614},{"lat":39.7330,"lng":-105.0520,"ele":1612},{"lat":39.7300,"lng":-105.0550,"ele":1610}]',
  5200, 15, 'road', true),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Sloan Lake Double',
  '[{"lat":39.7300,"lng":-105.0550,"ele":1610},{"lat":39.7350,"lng":-105.0500,"ele":1616},{"lat":39.7370,"lng":-105.0560,"ele":1620},{"lat":39.7330,"lng":-105.0600,"ele":1615},{"lat":39.7300,"lng":-105.0550,"ele":1610}]',
  10400, 35, 'trail', true),
-- Group E: long-distance band coverage
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Denver Marathon Route',
  '[{"lat":39.7200,"lng":-105.0000,"ele":1600},{"lat":39.7050,"lng":-105.0250,"ele":1640},{"lat":39.6950,"lng":-105.0400,"ele":1680},{"lat":39.6900,"lng":-105.0500,"ele":1700}]',
  42000, 320, 'road', true),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Front Range 50K',
  '[{"lat":39.7100,"lng":-105.0100,"ele":1640},{"lat":39.6900,"lng":-105.0400,"ele":1850},{"lat":39.6700,"lng":-105.0700,"ele":2100},{"lat":39.6500,"lng":-105.1000,"ele":2400}]',
  50000, 900, 'trail', true),
-- Group F: a followee-owned route (alex) for the `friends` lens
('b2c3d4e5-f6a7-8901-bcde-f23456789012', 'Alex''s Confluence Loop',
  '[{"lat":39.7550,"lng":-105.0250,"ele":1610},{"lat":39.7580,"lng":-105.0220,"ele":1614},{"lat":39.7560,"lng":-105.0280,"ele":1612},{"lat":39.7550,"lng":-105.0250,"ele":1610}]',
  8000, 24, 'road', true);

-- Lens states for the Denver testbed (see groups above). Featured +
-- run_count>0 → 'popular'; run_count=0 & not featured → 'hidden_gems';
-- Alex's route (run_count 0, not featured) only surfaces under 'friends'.
UPDATE routes SET is_featured = true, featured_at = now()
  WHERE name IN (
    'Wash Park 10K Spur',
    'City Park Sprint to Confluence',
    'City Park East',
    'Sloan Lake Loop CCW',
    'Denver Marathon Route'
  );
UPDATE routes SET run_count = 6 WHERE name = 'Wash Park 5K Loop';
UPDATE routes SET run_count = 4 WHERE name = 'Cherry Creek to Confluence';
UPDATE routes SET run_count = 2 WHERE name = 'Highline Canal Finish';
UPDATE routes SET run_count = 1 WHERE name = 'City Park North';
UPDATE routes SET run_count = 3 WHERE name = 'Sloan Lake Loop CW';
-- Keep the two exact-overlap groups (A: Wash Park, D: Sloan Lake) fully
-- popular so all three pins in each group show — and therefore cluster —
-- under the default lens. Un-run hidden-gem variety lives on City Park
-- South, Front Range 50K, and Alex's Confluence Loop instead.
UPDATE routes SET run_count = 1 WHERE name = 'Wash Park Half Adventure';
UPDATE routes SET run_count = 1 WHERE name = 'Sloan Lake Double';

-- ───────────────── Richmond, VA route density ─────────────────
--
-- A realistic spread of public routes around Richmond — the default
-- dev / demo city (bin/protomaps-dev.sh extracts Virginia tiles) — so
-- the discovery map looks lived-in when you open it on Richmond instead
-- of a near-empty handful. Real local running spots, distances spread
-- across the race-distance bands, and a mix of lens states (featured /
-- popular / un-run hidden gem / a followee-owned route for `friends`).
-- The discovery RPCs are all bbox-windowed + capped, so more routes
-- here don't slow the heatmap down — only what's in your viewport is
-- fetched, and at most 100 pins / 200 densified routes per call.
INSERT INTO routes (user_id, name, waypoints, distance_m, elevation_m, surface, is_public) VALUES
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Monument Avenue 10K',
  '[{"lat":37.5546,"lng":-77.4700,"ele":60},{"lat":37.5560,"lng":-77.4760,"ele":62},{"lat":37.5575,"lng":-77.4830,"ele":64},{"lat":37.5588,"lng":-77.4900,"ele":66}]',
  10000, 30, 'road', true),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Forest Hill Park Loop',
  '[{"lat":37.5200,"lng":-77.4800,"ele":70},{"lat":37.5215,"lng":-77.4770,"ele":78},{"lat":37.5205,"lng":-77.4745,"ele":74},{"lat":37.5190,"lng":-77.4775,"ele":68},{"lat":37.5200,"lng":-77.4800,"ele":70}]',
  4200, 45, 'trail', true),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Buttermilk Trail',
  '[{"lat":37.5300,"lng":-77.4650,"ele":55},{"lat":37.5285,"lng":-77.4580,"ele":62},{"lat":37.5278,"lng":-77.4500,"ele":70},{"lat":37.5270,"lng":-77.4420,"ele":66}]',
  8000, 95, 'trail', true),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'North Bank + Texas Beach',
  '[{"lat":37.5560,"lng":-77.4620,"ele":58},{"lat":37.5545,"lng":-77.4575,"ele":52},{"lat":37.5530,"lng":-77.4540,"ele":48},{"lat":37.5520,"lng":-77.4510,"ele":50}]',
  6500, 40, 'trail', true),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Byrd Park Vita Course',
  '[{"lat":37.5350,"lng":-77.4720,"ele":62},{"lat":37.5365,"lng":-77.4700,"ele":64},{"lat":37.5360,"lng":-77.4675,"ele":63},{"lat":37.5345,"lng":-77.4695,"ele":61},{"lat":37.5350,"lng":-77.4720,"ele":62}]',
  5000, 25, 'mixed', true),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Maymont Loop',
  '[{"lat":37.5310,"lng":-77.4830,"ele":58},{"lat":37.5325,"lng":-77.4815,"ele":72},{"lat":37.5315,"lng":-77.4795,"ele":66},{"lat":37.5300,"lng":-77.4815,"ele":56},{"lat":37.5310,"lng":-77.4830,"ele":58}]',
  3800, 55, 'mixed', true),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Bryan Park Perimeter',
  '[{"lat":37.6000,"lng":-77.4600,"ele":68},{"lat":37.6020,"lng":-77.4565,"ele":70},{"lat":37.6005,"lng":-77.4530,"ele":66},{"lat":37.5985,"lng":-77.4570,"ele":64}]',
  5500, 35, 'road', true),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Capital Trail to Rocketts',
  '[{"lat":37.5300,"lng":-77.4250,"ele":12},{"lat":37.5320,"lng":-77.4150,"ele":14},{"lat":37.5345,"lng":-77.4040,"ele":16},{"lat":37.5360,"lng":-77.3940,"ele":15}]',
  11000, 28, 'mixed', true),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Brown''s Island + Canal Walk',
  '[{"lat":37.5340,"lng":-77.4400,"ele":48},{"lat":37.5335,"lng":-77.4360,"ele":46},{"lat":37.5345,"lng":-77.4320,"ele":47},{"lat":37.5355,"lng":-77.4355,"ele":49}]',
  4800, 18, 'road', true),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Libby Hill Sprints',
  '[{"lat":37.5300,"lng":-77.4220,"ele":40},{"lat":37.5310,"lng":-77.4200,"ele":58},{"lat":37.5295,"lng":-77.4185,"ele":62},{"lat":37.5285,"lng":-77.4205,"ele":44}]',
  4500, 70, 'road', true),
('b2c3d4e5-f6a7-8901-bcde-f23456789012', 'Alex''s Fan District Loop',
  '[{"lat":37.5520,"lng":-77.4650,"ele":60},{"lat":37.5535,"lng":-77.4620,"ele":62},{"lat":37.5525,"lng":-77.4595,"ele":61},{"lat":37.5510,"lng":-77.4625,"ele":59},{"lat":37.5520,"lng":-77.4650,"ele":60}]',
  5200, 22, 'road', true);

-- Lens states for Richmond (see the comment above).
UPDATE routes SET is_featured = true, featured_at = now()
  WHERE name IN (
    'Monument Avenue 10K',
    'Brown''s Island + Canal Walk'
  );
UPDATE routes SET run_count = 5 WHERE name = 'Forest Hill Park Loop';
UPDATE routes SET run_count = 4 WHERE name = 'Buttermilk Trail';
UPDATE routes SET run_count = 3 WHERE name = 'North Bank + Texas Beach';
UPDATE routes SET run_count = 8 WHERE name = 'Byrd Park Vita Course';
UPDATE routes SET run_count = 2 WHERE name = 'Maymont Loop';
UPDATE routes SET run_count = 6 WHERE name = 'Capital Trail to Rocketts';
-- 'Bryan Park Perimeter' + 'Libby Hill Sprints' stay run_count 0 → hidden
-- gems; 'Alex''s Fan District Loop' stays 0 + alex-owned → friends only.

-- ───────── Real Richmond-area GPX traces (from the user's files) ─────────
-- Parsed + downsampled to ~70 points from real .gpx recordings:
-- the Richmond Marathon, Fendley Station Trail, and five Pocahontas
-- State Park trail routes. Real geometry so the hover-preview line +
-- elevation read like genuine runs, plus Half/Marathon-band coverage.
INSERT INTO routes (user_id, name, waypoints, distance_m, elevation_m, surface, is_public) VALUES
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Pocahontas State Park 16K',
  '[{"lat":37.38278,"lng":-77.57673,"ele":59},{"lat":37.3819,"lng":-77.57631,"ele":61},{"lat":37.38027,"lng":-77.57645,"ele":65},{"lat":37.37907,"lng":-77.57504,"ele":65},{"lat":37.37752,"lng":-77.57515,"ele":71},{"lat":37.3758,"lng":-77.57667,"ele":77},{"lat":37.37436,"lng":-77.57736,"ele":77},{"lat":37.37237,"lng":-77.57698,"ele":79},{"lat":37.3699,"lng":-77.57638,"ele":84},{"lat":37.37067,"lng":-77.57552,"ele":85},{"lat":37.37211,"lng":-77.57354,"ele":75},{"lat":37.3733,"lng":-77.57056,"ele":69},{"lat":37.37297,"lng":-77.56753,"ele":81},{"lat":37.37298,"lng":-77.56484,"ele":80},{"lat":37.37324,"lng":-77.56274,"ele":74},{"lat":37.37421,"lng":-77.56093,"ele":74},{"lat":37.37608,"lng":-77.56161,"ele":68},{"lat":37.37701,"lng":-77.55882,"ele":61},{"lat":37.37658,"lng":-77.55633,"ele":62},{"lat":37.37551,"lng":-77.55384,"ele":64},{"lat":37.37626,"lng":-77.55166,"ele":65},{"lat":37.37572,"lng":-77.54906,"ele":72},{"lat":37.37653,"lng":-77.54681,"ele":74},{"lat":37.3783,"lng":-77.54518,"ele":65},{"lat":37.37726,"lng":-77.54257,"ele":57},{"lat":37.37663,"lng":-77.53947,"ele":61},{"lat":37.3783,"lng":-77.53698,"ele":62},{"lat":37.38035,"lng":-77.53695,"ele":51},{"lat":37.38213,"lng":-77.53698,"ele":39},{"lat":37.38352,"lng":-77.53911,"ele":37},{"lat":37.38338,"lng":-77.5409,"ele":44},{"lat":37.3813,"lng":-77.5422,"ele":52},{"lat":37.37938,"lng":-77.54201,"ele":56},{"lat":37.37768,"lng":-77.54324,"ele":58},{"lat":37.37812,"lng":-77.54554,"ele":67},{"lat":37.37633,"lng":-77.5472,"ele":75},{"lat":37.37578,"lng":-77.54996,"ele":69},{"lat":37.37607,"lng":-77.55254,"ele":64},{"lat":37.37602,"lng":-77.55483,"ele":65},{"lat":37.3784,"lng":-77.55695,"ele":60},{"lat":37.38019,"lng":-77.55815,"ele":49},{"lat":37.38195,"lng":-77.55864,"ele":45},{"lat":37.38342,"lng":-77.5576,"ele":49},{"lat":37.38289,"lng":-77.55857,"ele":47},{"lat":37.38125,"lng":-77.55824,"ele":46},{"lat":37.37931,"lng":-77.55787,"ele":55},{"lat":37.3769,"lng":-77.55552,"ele":63},{"lat":37.37659,"lng":-77.55635,"ele":62},{"lat":37.37706,"lng":-77.55858,"ele":61},{"lat":37.37651,"lng":-77.56119,"ele":66},{"lat":37.37493,"lng":-77.56134,"ele":73},{"lat":37.37341,"lng":-77.56151,"ele":74},{"lat":37.37343,"lng":-77.56385,"ele":75},{"lat":37.37317,"lng":-77.56594,"ele":83},{"lat":37.37302,"lng":-77.56879,"ele":75},{"lat":37.37295,"lng":-77.57184,"ele":70},{"lat":37.37144,"lng":-77.57481,"ele":81},{"lat":37.36976,"lng":-77.57599,"ele":85},{"lat":37.37158,"lng":-77.57692,"ele":81},{"lat":37.37403,"lng":-77.57744,"ele":77},{"lat":37.37555,"lng":-77.57676,"ele":77},{"lat":37.3772,"lng":-77.57561,"ele":73},{"lat":37.37885,"lng":-77.57473,"ele":65},{"lat":37.38061,"lng":-77.57558,"ele":65},{"lat":37.38181,"lng":-77.57372,"ele":64},{"lat":37.38329,"lng":-77.57397,"ele":58},{"lat":37.38413,"lng":-77.57542,"ele":53},{"lat":37.38324,"lng":-77.57525,"ele":58},{"lat":37.3823,"lng":-77.57459,"ele":61},{"lat":37.38286,"lng":-77.57642,"ele":59}]',
  16175, 161, 'trail', true),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Pocahontas Swift Creek Half',
  '[{"lat":37.39765,"lng":-77.53569,"ele":65},{"lat":37.3968,"lng":-77.53743,"ele":64},{"lat":37.39856,"lng":-77.53906,"ele":65},{"lat":37.39901,"lng":-77.54215,"ele":69},{"lat":37.39963,"lng":-77.54798,"ele":73},{"lat":37.39727,"lng":-77.55007,"ele":76},{"lat":37.39753,"lng":-77.55296,"ele":79},{"lat":37.39748,"lng":-77.55592,"ele":84},{"lat":37.39787,"lng":-77.55708,"ele":83},{"lat":37.39705,"lng":-77.55914,"ele":76},{"lat":37.39336,"lng":-77.56116,"ele":68},{"lat":37.39383,"lng":-77.56307,"ele":65},{"lat":37.39422,"lng":-77.56612,"ele":61},{"lat":37.39433,"lng":-77.56961,"ele":55},{"lat":37.39527,"lng":-77.57069,"ele":52},{"lat":37.39366,"lng":-77.57272,"ele":52},{"lat":37.39419,"lng":-77.57378,"ele":53},{"lat":37.39231,"lng":-77.57406,"ele":52},{"lat":37.39012,"lng":-77.57526,"ele":49},{"lat":37.38939,"lng":-77.5762,"ele":47},{"lat":37.38808,"lng":-77.57742,"ele":51},{"lat":37.38723,"lng":-77.57813,"ele":52},{"lat":37.38617,"lng":-77.57916,"ele":49},{"lat":37.38506,"lng":-77.57809,"ele":47},{"lat":37.38405,"lng":-77.57927,"ele":46},{"lat":37.38353,"lng":-77.58064,"ele":44},{"lat":37.38444,"lng":-77.58137,"ele":44},{"lat":37.38474,"lng":-77.5826,"ele":47},{"lat":37.38532,"lng":-77.58335,"ele":50},{"lat":37.38693,"lng":-77.5847,"ele":53},{"lat":37.38615,"lng":-77.58753,"ele":52},{"lat":37.38504,"lng":-77.59011,"ele":48},{"lat":37.38351,"lng":-77.59111,"ele":47},{"lat":37.38244,"lng":-77.59281,"ele":46},{"lat":37.38051,"lng":-77.59221,"ele":47},{"lat":37.37905,"lng":-77.59377,"ele":51},{"lat":37.37823,"lng":-77.593,"ele":57},{"lat":37.37703,"lng":-77.58862,"ele":65},{"lat":37.37482,"lng":-77.58744,"ele":69},{"lat":37.37248,"lng":-77.58603,"ele":70},{"lat":37.36869,"lng":-77.58459,"ele":70},{"lat":37.36575,"lng":-77.58519,"ele":76},{"lat":37.36264,"lng":-77.58463,"ele":83},{"lat":37.3604,"lng":-77.58412,"ele":89},{"lat":37.361,"lng":-77.57953,"ele":89},{"lat":37.36111,"lng":-77.57755,"ele":90},{"lat":37.36401,"lng":-77.57416,"ele":91},{"lat":37.36603,"lng":-77.57358,"ele":91},{"lat":37.36809,"lng":-77.57066,"ele":90},{"lat":37.36935,"lng":-77.56852,"ele":88},{"lat":37.3707,"lng":-77.5653,"ele":86},{"lat":37.37145,"lng":-77.56328,"ele":82},{"lat":37.37225,"lng":-77.56088,"ele":79},{"lat":37.37221,"lng":-77.55738,"ele":75},{"lat":37.37296,"lng":-77.5529,"ele":73},{"lat":37.37375,"lng":-77.55073,"ele":71},{"lat":37.37472,"lng":-77.54807,"ele":70},{"lat":37.37429,"lng":-77.54401,"ele":66},{"lat":37.3736,"lng":-77.54131,"ele":65},{"lat":37.37648,"lng":-77.54092,"ele":62},{"lat":37.37901,"lng":-77.53633,"ele":56},{"lat":37.38173,"lng":-77.53683,"ele":39},{"lat":37.38225,"lng":-77.53698,"ele":39},{"lat":37.38272,"lng":-77.53741,"ele":39},{"lat":37.38463,"lng":-77.54043,"ele":41},{"lat":37.38611,"lng":-77.54022,"ele":50},{"lat":37.38798,"lng":-77.53882,"ele":60},{"lat":37.39113,"lng":-77.53977,"ele":68},{"lat":37.3939,"lng":-77.53826,"ele":68},{"lat":37.39799,"lng":-77.53508,"ele":65}]',
  20290, 109, 'trail', true),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Fendley Station Trail',
  '[{"lat":37.37354,"lng":-77.54127,"ele":63},{"lat":37.37429,"lng":-77.54402,"ele":63},{"lat":37.37514,"lng":-77.5471,"ele":73},{"lat":37.37421,"lng":-77.54825,"ele":72},{"lat":37.37314,"lng":-77.55174,"ele":72},{"lat":37.37232,"lng":-77.55618,"ele":74},{"lat":37.37226,"lng":-77.56088,"ele":81},{"lat":37.37104,"lng":-77.56484,"ele":85},{"lat":37.36938,"lng":-77.56831,"ele":88},{"lat":37.3681,"lng":-77.572,"ele":92},{"lat":37.36478,"lng":-77.57378,"ele":93},{"lat":37.36198,"lng":-77.57605,"ele":88},{"lat":37.36118,"lng":-77.57943,"ele":88},{"lat":37.36039,"lng":-77.58413,"ele":88},{"lat":37.3597,"lng":-77.58782,"ele":80},{"lat":37.36325,"lng":-77.58998,"ele":78},{"lat":37.36367,"lng":-77.58539,"ele":85},{"lat":37.36593,"lng":-77.58524,"ele":75},{"lat":37.36818,"lng":-77.58573,"ele":62},{"lat":37.3691,"lng":-77.58445,"ele":69},{"lat":37.37151,"lng":-77.58524,"ele":76},{"lat":37.3737,"lng":-77.58553,"ele":71},{"lat":37.37482,"lng":-77.58745,"ele":68},{"lat":37.37671,"lng":-77.58845,"ele":69},{"lat":37.37831,"lng":-77.59145,"ele":59},{"lat":37.37884,"lng":-77.59374,"ele":51},{"lat":37.38078,"lng":-77.59475,"ele":59},{"lat":37.37929,"lng":-77.59734,"ele":70},{"lat":37.3776,"lng":-77.59958,"ele":76},{"lat":37.37939,"lng":-77.59921,"ele":66},{"lat":37.38256,"lng":-77.59734,"ele":60},{"lat":37.38495,"lng":-77.59685,"ele":63},{"lat":37.38737,"lng":-77.59518,"ele":65},{"lat":37.38712,"lng":-77.59186,"ele":65},{"lat":37.38834,"lng":-77.58947,"ele":69},{"lat":37.38863,"lng":-77.58595,"ele":71},{"lat":37.38783,"lng":-77.58323,"ele":66},{"lat":37.38766,"lng":-77.58179,"ele":62},{"lat":37.388,"lng":-77.58011,"ele":57},{"lat":37.38908,"lng":-77.5769,"ele":45},{"lat":37.39024,"lng":-77.57598,"ele":45},{"lat":37.39248,"lng":-77.57482,"ele":50},{"lat":37.39394,"lng":-77.57344,"ele":54},{"lat":37.39486,"lng":-77.57156,"ele":52},{"lat":37.39443,"lng":-77.56979,"ele":54},{"lat":37.39406,"lng":-77.56601,"ele":66},{"lat":37.39379,"lng":-77.56293,"ele":67},{"lat":37.39425,"lng":-77.56133,"ele":64},{"lat":37.39705,"lng":-77.55914,"ele":76},{"lat":37.39754,"lng":-77.55691,"ele":87},{"lat":37.3976,"lng":-77.55527,"ele":84},{"lat":37.39738,"lng":-77.55221,"ele":74},{"lat":37.39788,"lng":-77.55046,"ele":74},{"lat":37.39959,"lng":-77.54922,"ele":79},{"lat":37.39993,"lng":-77.54503,"ele":72},{"lat":37.39897,"lng":-77.54078,"ele":67},{"lat":37.39726,"lng":-77.53854,"ele":65},{"lat":37.39774,"lng":-77.53622,"ele":65},{"lat":37.39593,"lng":-77.53732,"ele":62},{"lat":37.39281,"lng":-77.53916,"ele":67},{"lat":37.3907,"lng":-77.53884,"ele":69},{"lat":37.38856,"lng":-77.53815,"ele":64},{"lat":37.38646,"lng":-77.53945,"ele":55},{"lat":37.38521,"lng":-77.54091,"ele":46},{"lat":37.38421,"lng":-77.5405,"ele":39},{"lat":37.38199,"lng":-77.5369,"ele":41},{"lat":37.3792,"lng":-77.53632,"ele":59},{"lat":37.37677,"lng":-77.53909,"ele":63},{"lat":37.37583,"lng":-77.54072,"ele":63},{"lat":37.37349,"lng":-77.54122,"ele":64}]',
  20921, 173, 'trail', true),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Pocahontas Lakeview Loop',
  '[{"lat":37.36038,"lng":-77.58416,"ele":90},{"lat":37.36098,"lng":-77.5812,"ele":85},{"lat":37.36124,"lng":-77.57858,"ele":91},{"lat":37.36304,"lng":-77.57498,"ele":91},{"lat":37.36545,"lng":-77.57373,"ele":87},{"lat":37.36828,"lng":-77.57167,"ele":89},{"lat":37.36939,"lng":-77.56811,"ele":89},{"lat":37.37068,"lng":-77.56528,"ele":87},{"lat":37.37193,"lng":-77.5624,"ele":82},{"lat":37.3721,"lng":-77.56,"ele":80},{"lat":37.37214,"lng":-77.5576,"ele":75},{"lat":37.37296,"lng":-77.55288,"ele":72},{"lat":37.37373,"lng":-77.55073,"ele":71},{"lat":37.3745,"lng":-77.54803,"ele":72},{"lat":37.37476,"lng":-77.54571,"ele":67},{"lat":37.37403,"lng":-77.54236,"ele":64},{"lat":37.37523,"lng":-77.5406,"ele":62},{"lat":37.37652,"lng":-77.53962,"ele":61},{"lat":37.37918,"lng":-77.53631,"ele":61},{"lat":37.38175,"lng":-77.53683,"ele":37},{"lat":37.38394,"lng":-77.54013,"ele":42},{"lat":37.38519,"lng":-77.5409,"ele":46},{"lat":37.3866,"lng":-77.53932,"ele":57},{"lat":37.38991,"lng":-77.53773,"ele":70},{"lat":37.39334,"lng":-77.53867,"ele":68},{"lat":37.39544,"lng":-77.53734,"ele":60},{"lat":37.39776,"lng":-77.53631,"ele":66},{"lat":37.3975,"lng":-77.53871,"ele":62},{"lat":37.39883,"lng":-77.54004,"ele":68},{"lat":37.39916,"lng":-77.54265,"ele":67},{"lat":37.39969,"lng":-77.54858,"ele":75},{"lat":37.39695,"lng":-77.55077,"ele":72},{"lat":37.39738,"lng":-77.55258,"ele":78},{"lat":37.39746,"lng":-77.55592,"ele":86},{"lat":37.39772,"lng":-77.55704,"ele":86},{"lat":37.39703,"lng":-77.55914,"ele":76},{"lat":37.39398,"lng":-77.56137,"ele":64},{"lat":37.39398,"lng":-77.56373,"ele":71},{"lat":37.39287,"lng":-77.56657,"ele":70},{"lat":37.39188,"lng":-77.57082,"ele":60},{"lat":37.39248,"lng":-77.5739,"ele":56},{"lat":37.39047,"lng":-77.57515,"ele":51},{"lat":37.38974,"lng":-77.57609,"ele":40},{"lat":37.38793,"lng":-77.57532,"ele":39},{"lat":37.38703,"lng":-77.57618,"ele":43},{"lat":37.38613,"lng":-77.57854,"ele":48},{"lat":37.38506,"lng":-77.57811,"ele":44},{"lat":37.38407,"lng":-77.57927,"ele":50},{"lat":37.38351,"lng":-77.58064,"ele":44},{"lat":37.3842,"lng":-77.58111,"ele":43},{"lat":37.38476,"lng":-77.5821,"ele":45},{"lat":37.38544,"lng":-77.58343,"ele":49},{"lat":37.38793,"lng":-77.58373,"ele":68},{"lat":37.38871,"lng":-77.58712,"ele":68},{"lat":37.38755,"lng":-77.59141,"ele":62},{"lat":37.38759,"lng":-77.59586,"ele":62},{"lat":37.3848,"lng":-77.59686,"ele":61},{"lat":37.38369,"lng":-77.59699,"ele":63},{"lat":37.3772,"lng":-77.6006,"ele":72},{"lat":37.37987,"lng":-77.59704,"ele":65},{"lat":37.38055,"lng":-77.59356,"ele":56},{"lat":37.37828,"lng":-77.59309,"ele":50},{"lat":37.3769,"lng":-77.58854,"ele":70},{"lat":37.3748,"lng":-77.58747,"ele":68},{"lat":37.37283,"lng":-77.58601,"ele":71},{"lat":37.37052,"lng":-77.58482,"ele":76},{"lat":37.36824,"lng":-77.58566,"ele":62},{"lat":37.36575,"lng":-77.58519,"ele":78},{"lat":37.36248,"lng":-77.58451,"ele":84},{"lat":37.36036,"lng":-77.58439,"ele":89}]',
  21324, 189, 'trail', true),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Pocahontas Beaver Lake Half',
  '[{"lat":37.39797,"lng":-77.53511,"ele":64},{"lat":37.39619,"lng":-77.53726,"ele":61},{"lat":37.39178,"lng":-77.54036,"ele":66},{"lat":37.39257,"lng":-77.5422,"ele":64},{"lat":37.3947,"lng":-77.54472,"ele":63},{"lat":37.39452,"lng":-77.54655,"ele":67},{"lat":37.39564,"lng":-77.54926,"ele":68},{"lat":37.39739,"lng":-77.5518,"ele":74},{"lat":37.3976,"lng":-77.55527,"ele":84},{"lat":37.39617,"lng":-77.55627,"ele":78},{"lat":37.39441,"lng":-77.55535,"ele":67},{"lat":37.39163,"lng":-77.55573,"ele":66},{"lat":37.3905,"lng":-77.55756,"ele":58},{"lat":37.38982,"lng":-77.55871,"ele":60},{"lat":37.38846,"lng":-77.56012,"ele":67},{"lat":37.38644,"lng":-77.56087,"ele":56},{"lat":37.38555,"lng":-77.56255,"ele":45},{"lat":37.38657,"lng":-77.5651,"ele":44},{"lat":37.38772,"lng":-77.5679,"ele":45},{"lat":37.38791,"lng":-77.56891,"ele":46},{"lat":37.38748,"lng":-77.57004,"ele":47},{"lat":37.38706,"lng":-77.57111,"ele":46},{"lat":37.38711,"lng":-77.57325,"ele":44},{"lat":37.38892,"lng":-77.57314,"ele":43},{"lat":37.39111,"lng":-77.57387,"ele":47},{"lat":37.38996,"lng":-77.57575,"ele":44},{"lat":37.38876,"lng":-77.57725,"ele":46},{"lat":37.38802,"lng":-77.58044,"ele":59},{"lat":37.38773,"lng":-77.58234,"ele":64},{"lat":37.38719,"lng":-77.58426,"ele":59},{"lat":37.38717,"lng":-77.58564,"ele":55},{"lat":37.38619,"lng":-77.5874,"ele":54},{"lat":37.38581,"lng":-77.58935,"ele":46},{"lat":37.38437,"lng":-77.59035,"ele":44},{"lat":37.38315,"lng":-77.59161,"ele":50},{"lat":37.38198,"lng":-77.59323,"ele":46},{"lat":37.38056,"lng":-77.59245,"ele":46},{"lat":37.37941,"lng":-77.59372,"ele":51},{"lat":37.37833,"lng":-77.59191,"ele":56},{"lat":37.37682,"lng":-77.58849,"ele":68},{"lat":37.37494,"lng":-77.58777,"ele":68},{"lat":37.37377,"lng":-77.58552,"ele":70},{"lat":37.37175,"lng":-77.58541,"ele":75},{"lat":37.36916,"lng":-77.58443,"ele":70},{"lat":37.36827,"lng":-77.58556,"ele":61},{"lat":37.36609,"lng":-77.5853,"ele":73},{"lat":37.36369,"lng":-77.58539,"ele":83},{"lat":37.36149,"lng":-77.58925,"ele":79},{"lat":37.36048,"lng":-77.58349,"ele":87},{"lat":37.36144,"lng":-77.57898,"ele":88},{"lat":37.36401,"lng":-77.57417,"ele":92},{"lat":37.36823,"lng":-77.57188,"ele":90},{"lat":37.37035,"lng":-77.56607,"ele":87},{"lat":37.37203,"lng":-77.56226,"ele":82},{"lat":37.37212,"lng":-77.5576,"ele":75},{"lat":37.37305,"lng":-77.55136,"ele":71},{"lat":37.37444,"lng":-77.54802,"ele":72},{"lat":37.37491,"lng":-77.54673,"ele":71},{"lat":37.3743,"lng":-77.54368,"ele":62},{"lat":37.37474,"lng":-77.5408,"ele":63},{"lat":37.37645,"lng":-77.53993,"ele":63},{"lat":37.37889,"lng":-77.53638,"ele":61},{"lat":37.38173,"lng":-77.53684,"ele":44},{"lat":37.38475,"lng":-77.54045,"ele":40},{"lat":37.38539,"lng":-77.54088,"ele":47},{"lat":37.38725,"lng":-77.53907,"ele":56},{"lat":37.38941,"lng":-77.53771,"ele":67},{"lat":37.39178,"lng":-77.54013,"ele":68},{"lat":37.39619,"lng":-77.53726,"ele":61},{"lat":37.39796,"lng":-77.53512,"ele":63}]',
  21694, 164, 'trail', true),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Pocahontas Ridge Half',
  '[{"lat":37.38832,"lng":-77.57986,"ele":58},{"lat":37.38655,"lng":-77.58219,"ele":57},{"lat":37.38864,"lng":-77.58703,"ele":69},{"lat":37.38714,"lng":-77.59173,"ele":65},{"lat":37.38749,"lng":-77.59582,"ele":62},{"lat":37.38655,"lng":-77.59614,"ele":67},{"lat":37.38409,"lng":-77.5974,"ele":67},{"lat":37.38104,"lng":-77.59807,"ele":58},{"lat":37.3786,"lng":-77.59789,"ele":71},{"lat":37.38075,"lng":-77.59528,"ele":59},{"lat":37.379,"lng":-77.59374,"ele":54},{"lat":37.37836,"lng":-77.59153,"ele":58},{"lat":37.37566,"lng":-77.58851,"ele":63},{"lat":37.37451,"lng":-77.58602,"ele":70},{"lat":37.37262,"lng":-77.58602,"ele":72},{"lat":37.36868,"lng":-77.58471,"ele":68},{"lat":37.36714,"lng":-77.58578,"ele":65},{"lat":37.36378,"lng":-77.58542,"ele":83},{"lat":37.36424,"lng":-77.5878,"ele":82},{"lat":37.36222,"lng":-77.58995,"ele":80},{"lat":37.35996,"lng":-77.5856,"ele":86},{"lat":37.36103,"lng":-77.58155,"ele":88},{"lat":37.36148,"lng":-77.57936,"ele":87},{"lat":37.364,"lng":-77.57424,"ele":96},{"lat":37.36685,"lng":-77.57291,"ele":94},{"lat":37.36787,"lng":-77.57395,"ele":93},{"lat":37.36849,"lng":-77.57282,"ele":92},{"lat":37.36957,"lng":-77.56763,"ele":89},{"lat":37.37102,"lng":-77.565,"ele":83},{"lat":37.37201,"lng":-77.56221,"ele":82},{"lat":37.37207,"lng":-77.56032,"ele":83},{"lat":37.37192,"lng":-77.55797,"ele":76},{"lat":37.37293,"lng":-77.55281,"ele":72},{"lat":37.37309,"lng":-77.55102,"ele":72},{"lat":37.37409,"lng":-77.5485,"ele":71},{"lat":37.37441,"lng":-77.54458,"ele":64},{"lat":37.37373,"lng":-77.54134,"ele":64},{"lat":37.37631,"lng":-77.5403,"ele":64},{"lat":37.37845,"lng":-77.53664,"ele":63},{"lat":37.37957,"lng":-77.5365,"ele":59},{"lat":37.38245,"lng":-77.53725,"ele":43},{"lat":37.38398,"lng":-77.54039,"ele":41},{"lat":37.38607,"lng":-77.5403,"ele":50},{"lat":37.38853,"lng":-77.53826,"ele":64},{"lat":37.39113,"lng":-77.53979,"ele":66},{"lat":37.39297,"lng":-77.53896,"ele":68},{"lat":37.39623,"lng":-77.53729,"ele":60},{"lat":37.39766,"lng":-77.53654,"ele":66},{"lat":37.39679,"lng":-77.53817,"ele":62},{"lat":37.3983,"lng":-77.53889,"ele":65},{"lat":37.39958,"lng":-77.54366,"ele":69},{"lat":37.39968,"lng":-77.54721,"ele":71},{"lat":37.39752,"lng":-77.55006,"ele":69},{"lat":37.39739,"lng":-77.55173,"ele":71},{"lat":37.39729,"lng":-77.5543,"ele":79},{"lat":37.39778,"lng":-77.55718,"ele":85},{"lat":37.39518,"lng":-77.56006,"ele":70},{"lat":37.3933,"lng":-77.56112,"ele":61},{"lat":37.39393,"lng":-77.56403,"ele":70},{"lat":37.39256,"lng":-77.56836,"ele":70},{"lat":37.39189,"lng":-77.56851,"ele":74},{"lat":37.38997,"lng":-77.57005,"ele":61},{"lat":37.39203,"lng":-77.56793,"ele":75},{"lat":37.39172,"lng":-77.57021,"ele":63},{"lat":37.39234,"lng":-77.57386,"ele":55},{"lat":37.39095,"lng":-77.57475,"ele":52},{"lat":37.38875,"lng":-77.57721,"ele":49},{"lat":37.38793,"lng":-77.57806,"ele":56},{"lat":37.38792,"lng":-77.57888,"ele":56},{"lat":37.38848,"lng":-77.57983,"ele":58}]',
  22290, 178, 'trail', true),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Richmond Marathon',
  '[{"lat":37.5451,"lng":-77.44122,"ele":53},{"lat":37.55279,"lng":-77.45404,"ele":59},{"lat":37.56047,"lng":-77.46696,"ele":62},{"lat":37.56457,"lng":-77.47833,"ele":64},{"lat":37.57172,"lng":-77.49028,"ele":66},{"lat":37.56545,"lng":-77.49946,"ele":71},{"lat":37.57197,"lng":-77.51331,"ele":74},{"lat":37.57008,"lng":-77.52051,"ele":78},{"lat":37.5681,"lng":-77.53222,"ele":50},{"lat":37.56737,"lng":-77.53905,"ele":37},{"lat":37.56637,"lng":-77.5418,"ele":38},{"lat":37.56452,"lng":-77.54332,"ele":38},{"lat":37.55772,"lng":-77.5446,"ele":40},{"lat":37.55849,"lng":-77.5413,"ele":36},{"lat":37.55911,"lng":-77.53551,"ele":33},{"lat":37.55922,"lng":-77.53054,"ele":33},{"lat":37.55808,"lng":-77.52786,"ele":32},{"lat":37.5546,"lng":-77.52559,"ele":32},{"lat":37.55214,"lng":-77.5222,"ele":31},{"lat":37.55013,"lng":-77.52154,"ele":31},{"lat":37.54831,"lng":-77.51809,"ele":30},{"lat":37.54682,"lng":-77.51749,"ele":39},{"lat":37.5429,"lng":-77.51804,"ele":50},{"lat":37.5416,"lng":-77.51583,"ele":50},{"lat":37.53929,"lng":-77.51501,"ele":51},{"lat":37.53774,"lng":-77.5154,"ele":49},{"lat":37.53556,"lng":-77.51108,"ele":48},{"lat":37.53451,"lng":-77.50848,"ele":37},{"lat":37.53308,"lng":-77.50745,"ele":44},{"lat":37.53086,"lng":-77.50542,"ele":56},{"lat":37.52625,"lng":-77.49807,"ele":62},{"lat":37.52015,"lng":-77.48367,"ele":60},{"lat":37.51594,"lng":-77.46951,"ele":50},{"lat":37.52185,"lng":-77.45449,"ele":36},{"lat":37.52529,"lng":-77.45388,"ele":36},{"lat":37.52587,"lng":-77.45201,"ele":29},{"lat":37.52554,"lng":-77.45128,"ele":25},{"lat":37.52502,"lng":-77.45126,"ele":29},{"lat":37.52492,"lng":-77.45202,"ele":30},{"lat":37.52555,"lng":-77.45223,"ele":32},{"lat":37.52822,"lng":-77.45136,"ele":19},{"lat":37.53357,"lng":-77.44937,"ele":14},{"lat":37.53564,"lng":-77.44916,"ele":39},{"lat":37.54375,"lng":-77.44894,"ele":50},{"lat":37.54702,"lng":-77.45973,"ele":61},{"lat":37.55152,"lng":-77.47239,"ele":67},{"lat":37.56174,"lng":-77.47053,"ele":62},{"lat":37.56901,"lng":-77.46656,"ele":61},{"lat":37.57402,"lng":-77.46379,"ele":62},{"lat":37.57651,"lng":-77.46238,"ele":64},{"lat":37.57862,"lng":-77.4614,"ele":62},{"lat":37.58125,"lng":-77.46187,"ele":61},{"lat":37.58472,"lng":-77.4625,"ele":59},{"lat":37.58706,"lng":-77.46352,"ele":58},{"lat":37.59094,"lng":-77.46378,"ele":58},{"lat":37.59381,"lng":-77.46188,"ele":58},{"lat":37.59348,"lng":-77.45932,"ele":57},{"lat":37.58778,"lng":-77.45559,"ele":60},{"lat":37.57993,"lng":-77.45044,"ele":60},{"lat":37.57568,"lng":-77.44966,"ele":59},{"lat":37.57146,"lng":-77.44932,"ele":59},{"lat":37.56566,"lng":-77.44873,"ele":53},{"lat":37.56068,"lng":-77.45018,"ele":53},{"lat":37.55967,"lng":-77.45111,"ele":52},{"lat":37.55336,"lng":-77.45687,"ele":59},{"lat":37.54603,"lng":-77.44483,"ele":54},{"lat":37.54033,"lng":-77.43994,"ele":50},{"lat":37.5381,"lng":-77.44206,"ele":34},{"lat":37.53665,"lng":-77.44338,"ele":23},{"lat":37.53545,"lng":-77.44345,"ele":19}]',
  42195, 147, 'road', true);

-- Lens states for the real GPX routes. The two ~13mi Pocahontas routes
-- (Swift Creek + Beaver Lake Half) share a trailhead ~40 m apart, so
-- their start pins overlap — a real same-start case to test the cluster
-- list + the overlapping-leaf hover handling.
UPDATE routes SET is_featured = true, featured_at = now()
  WHERE name IN ('Richmond Marathon', 'Pocahontas Lakeview Loop');
UPDATE routes SET run_count = 7 WHERE name = 'Pocahontas Swift Creek Half';
UPDATE routes SET run_count = 5 WHERE name = 'Pocahontas Beaver Lake Half';
UPDATE routes SET run_count = 4 WHERE name = 'Fendley Station Trail';
UPDATE routes SET run_count = 3 WHERE name = 'Pocahontas State Park 16K';
-- 'Pocahontas Ridge Half' stays run_count 0 → hidden gem.

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

-- 3a. Pre-grant GDPR consent timestamps for all three seed users so
-- the Coach + Preferences surfaces render past the consent gates in
-- test runs. Real users have to click the disclosure (migration
-- 20260921_001 + the /coach + /settings/preferences UI); the seed
-- short-circuits that for e2e + manual dev convenience. The dedicated
-- consent-gate tests (web src/lib/security_guards.test.ts, mobile
-- coach_screen_test.dart) are source-grep guards over the handler
-- code, so pre-seeded consent doesn't bypass them.
UPDATE user_profiles
   SET coach_consent_at = now(),
       health_data_consent_at = now()
 WHERE id IN (
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
   'b2c3d4e5-f6a7-8901-bcde-f23456789012',
   'c3d4e5f6-a7b8-9012-cdef-345678901234'
 );

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
  -- The rate_limits.user_id FK to auth.users (migration 20260928_001)
  -- means these synthetic UUIDs must exist before any insert lands.
  -- Same pattern as the route_reviews RLS test block below.
  INSERT INTO auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    VALUES (test_user, 'rate-limit-test-1@example.com', '',
            now(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    VALUES (test_user2, 'rate-limit-test-2@example.com', '',
            now(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated')
    ON CONFLICT (id) DO NOTHING;
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

  -- The FK was rolled back in 20261003_001 — drop the rate_limit
  -- rows directly + the synthetic auth users; no cascade.
  DELETE FROM rate_limits WHERE user_id IN (test_user, test_user2);
  DELETE FROM auth.users WHERE id IN (test_user, test_user2);
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

-- ───────── live_run_pings privacy clipping (migrations 20260618_001 + 20270121_001) ─────────
-- Verifies the BEFORE INSERT trigger's privacy-vs-safety carve-out: an
-- out-of-zone ping lands precise, and an in-zone ping is no longer
-- dropped outright but COARSENED-AND-KEPT as a single `coarse=true`
-- last-seen point (migration 20270121_001) — so a runner who stops
-- inside their own zone still shows a ~1 km last-known position to the
-- spectator / SAR feed. This is the surface Realtime broadcasts to
-- /live/{run_id} subscribers.
DO $$
DECLARE
  test_user uuid := 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
  test_run_id uuid;
  v_count_before int;
  v_count_after int;
  v_coarse_count int;
  v_coarse_lat double precision;
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

  -- Out-of-zone ping (~5km north): should land precise.
  INSERT INTO live_run_pings (run_id, user_id, lat, lng)
    VALUES (test_run_id, test_user, 40.045, -74.0);

  -- In-zone ping (~55m offset): the carve-out keeps it as a single
  -- coarsened (2-dp, ~1km) last-seen point rather than dropping it.
  INSERT INTO live_run_pings (run_id, user_id, lat, lng)
    VALUES (test_run_id, test_user, 40.0005, -74.0);

  SELECT count(*) INTO v_count_after FROM live_run_pings WHERE run_id = test_run_id;
  IF v_count_after - v_count_before <> 2 THEN
    RAISE EXCEPTION 'live_run_pings privacy carve-out: expected 2 pings to land (precise out-of-zone + coarsened in-zone), got delta=%', v_count_after - v_count_before;
  END IF;

  -- Exactly one of them is the coarsened in-zone last-seen point, and it
  -- is rounded to the 2-dp grid (never the exact 40.0005 zone-edge point).
  SELECT count(*) INTO v_coarse_count
    FROM live_run_pings WHERE run_id = test_run_id AND coarse = true;
  IF v_coarse_count <> 1 THEN
    RAISE EXCEPTION 'live_run_pings privacy carve-out: expected exactly 1 coarse last-seen ping, got %', v_coarse_count;
  END IF;
  SELECT lat INTO v_coarse_lat
    FROM live_run_pings WHERE run_id = test_run_id AND coarse = true;
  IF v_coarse_lat <> 40.0 THEN
    RAISE EXCEPTION 'live_run_pings privacy carve-out: coarse ping lat should be 2-dp (40.0), got %', v_coarse_lat;
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
  -- (per docs/backend/metadata.md classification + the 20260714_001 strip
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
  INSERT INTO events (club_id, title, starts_at, author_id)
    VALUES (v_private_club_id, 'private event', v_instance, other_user)
    RETURNING id INTO v_private_event_id;
  INSERT INTO events (club_id, title, starts_at, author_id)
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

-- ---------------------------------------------------------------------------
-- Phase 4 multi-modal seed: gym + nutrition for runner@test.com
--
-- Dates are now()-relative (not the fixed May 2026 dates the run history
-- uses) because /nutrition keys off "today" + the last 7 days and /gym is a
-- recency list — fixed dates would leave both surfaces empty on any reset
-- run after that day. The e2e suites seed their own uniquely-named rows
-- (tests-e2e/gym, tests-e2e/nutrition) so these static rows don't collide.
-- ---------------------------------------------------------------------------

-- Body-metrics weight series (latest row feeds the nutrition BMR + the
-- dashboard weight trend). A gentle downward drift over three weeks.
INSERT INTO body_metrics (user_id, recorded_at, weight_kg) VALUES
  ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', now() - interval '21 days', 75.4),
  ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', now() - interval '14 days', 74.8),
  ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', now() - interval '7 days',  74.2),
  ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', now() - interval '1 day',   73.9);

-- Gym workouts — three sessions, oldest first. The set_count / volume_kg
-- columns are trigger-maintained (migration 20261214_001), so we insert the
-- workout shells then the sets; the trigger recomputes totals. Progressive
-- overload across the two Push days earns weight/volume/e1RM PR badges on
-- /gym + per-exercise PR chips on the latest /gym/[id].
INSERT INTO gym_workouts (id, user_id, title, started_at, duration_s, notes) VALUES
  ('a2000001-0000-0000-0000-000000000001', 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    'Push day', now() - interval '16 days', 3600, 'Felt strong, bumped the bench next time.'),
  ('a2000001-0000-0000-0000-000000000002', 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    'Lower body', now() - interval '9 days', 4200, NULL),
  ('a2000001-0000-0000-0000-000000000003', 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    'Push day', now() - interval '2 days', 3900, 'New bench top set. Overhead press up too.');

INSERT INTO gym_sets (workout_id, set_index, exercise_name, reps, weight_kg, rpe) VALUES
  -- Push day (16 days ago) — baseline
  ('a2000001-0000-0000-0000-000000000001', 0, 'Bench press', 5, 60.0, 8.0),
  ('a2000001-0000-0000-0000-000000000001', 1, 'Bench press', 5, 60.0, 8.0),
  ('a2000001-0000-0000-0000-000000000001', 2, 'Bench press', 5, 60.0, 8.5),
  ('a2000001-0000-0000-0000-000000000001', 3, 'Overhead press', 8, 35.0, 8.0),
  ('a2000001-0000-0000-0000-000000000001', 4, 'Overhead press', 8, 35.0, 8.5),
  ('a2000001-0000-0000-0000-000000000001', 5, 'Overhead press', 7, 35.0, 9.0),
  ('a2000001-0000-0000-0000-000000000001', 6, 'Pull-up', 8, NULL, 8.0),
  ('a2000001-0000-0000-0000-000000000001', 7, 'Pull-up', 7, NULL, 8.5),
  -- Lower body (9 days ago) — first time on these lifts
  ('a2000001-0000-0000-0000-000000000002', 0, 'Back squat', 5, 90.0, 8.0),
  ('a2000001-0000-0000-0000-000000000002', 1, 'Back squat', 5, 90.0, 8.0),
  ('a2000001-0000-0000-0000-000000000002', 2, 'Back squat', 5, 90.0, 8.5),
  ('a2000001-0000-0000-0000-000000000002', 3, 'Romanian deadlift', 8, 70.0, 7.5),
  ('a2000001-0000-0000-0000-000000000002', 4, 'Romanian deadlift', 8, 70.0, 8.0),
  ('a2000001-0000-0000-0000-000000000002', 5, 'Leg press', 12, 140.0, 8.0),
  ('a2000001-0000-0000-0000-000000000002', 6, 'Leg press', 12, 140.0, 8.5),
  -- Push day (2 days ago) — beats the first Push day
  ('a2000001-0000-0000-0000-000000000003', 0, 'Bench press', 5, 65.0, 8.5),
  ('a2000001-0000-0000-0000-000000000003', 1, 'Bench press', 5, 65.0, 9.0),
  ('a2000001-0000-0000-0000-000000000003', 2, 'Bench press', 4, 65.0, 9.0),
  ('a2000001-0000-0000-0000-000000000003', 3, 'Overhead press', 6, 37.5, 8.5),
  ('a2000001-0000-0000-0000-000000000003', 4, 'Overhead press', 6, 37.5, 9.0),
  ('a2000001-0000-0000-0000-000000000003', 5, 'Overhead press', 6, 37.5, 9.0),
  ('a2000001-0000-0000-0000-000000000003', 6, 'Pull-up', 9, NULL, 8.0),
  ('a2000001-0000-0000-0000-000000000003', 7, 'Pull-up', 8, NULL, 8.5);

-- Food log — today's four meal slots (full macros so the rings + meal chips
-- fill) plus six prior days of lunch+dinner pairs so the 7-day calorie trend
-- has variation.
INSERT INTO food_log (user_id, started_at, item_name, meal_slot, calories, protein_g, carbs_g, fat_g) VALUES
  -- Today
  ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', now() - interval '8 hours', 'Oatmeal with banana & peanut butter', 'breakfast', 420, 14, 62, 12),
  ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', now() - interval '5 hours', 'Greek yogurt & berries', 'snack', 180, 17, 20, 3),
  ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', now() - interval '4 hours', 'Grilled chicken, rice & vegetables', 'lunch', 650, 48, 72, 16),
  ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', now() - interval '1 hour',  'Salmon, sweet potato & broccoli', 'dinner', 720, 45, 55, 32),
  -- Prior days (lunch + dinner)
  ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', now() - interval '1 day' - interval '6 hours', 'Turkey & avocado wrap', 'lunch', 560, 34, 48, 24),
  ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', now() - interval '1 day' - interval '2 hours', 'Beef stir-fry with noodles', 'dinner', 780, 42, 80, 26),
  ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', now() - interval '2 days' - interval '6 hours', 'Lentil soup & sourdough', 'lunch', 480, 22, 68, 10),
  ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', now() - interval '2 days' - interval '2 hours', 'Margherita pizza (half)', 'dinner', 720, 28, 88, 26),
  ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', now() - interval '3 days' - interval '6 hours', 'Chicken caesar salad', 'lunch', 520, 40, 18, 32),
  ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', now() - interval '3 days' - interval '2 hours', 'Spaghetti bolognese', 'dinner', 850, 46, 92, 28),
  ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', now() - interval '4 days' - interval '6 hours', 'Tuna poke bowl', 'lunch', 610, 38, 66, 20),
  ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', now() - interval '4 days' - interval '2 hours', 'Chicken curry & rice', 'dinner', 740, 44, 78, 24),
  ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', now() - interval '5 days' - interval '6 hours', 'Egg & spinach omelette', 'lunch', 430, 30, 8, 30),
  ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', now() - interval '5 days' - interval '2 hours', 'Veggie burrito bowl', 'dinner', 690, 26, 84, 24),
  ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', now() - interval '6 days' - interval '6 hours', 'Ham & cheese sandwich', 'lunch', 540, 28, 52, 22),
  ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', now() - interval '6 days' - interval '2 hours', 'Roast chicken & potatoes', 'dinner', 760, 50, 62, 28);

-- One run earlier today so the dynamic-TDEE "base + exercise" breakdown is
-- visible on /nutrition out of the box (and today's effort feeds the dashboard
-- readiness curve). now()-relative for the same reason as the rows above. No
-- track/route — the estimator only needs distance_m.
INSERT INTO runs (user_id, started_at, duration_s, distance_m, source, is_public, metadata) VALUES
  ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', now() - interval '3 hours', 1980, 8000.0, 'app', false,
    '{"activity_type":"run","title":"Morning easy 8K","avg_bpm":148,"steps":9800}'::jsonb);

-- ════════════════════════════════════════════════════════════════════════════
-- Club templates for Richmond Run Club — so the Templates tab is populated.
--
-- runner@test.com owns Richmond Run Club, so these club-owned templates appear
-- in the club's Templates tab (Training plan / Session / Gym routine sections),
-- are adoptable by members, and (being authored by runner) also surface on the
-- owner's own /plans, /sessions, and /gym/routines lists. Fixed ids keep the
-- reset idempotent.
-- ════════════════════════════════════════════════════════════════════════════

-- ── Training plan template ──────────────────────────────────────────────────
-- is_template = true + club_id set. status must not be 'active' (a template
-- can't claim the per-user active-plan slot — migration 20260524_001).
INSERT INTO training_plans (
  id, user_id, name, goal_event, goal_distance_m, goal_time_seconds,
  start_date, end_date, days_per_week, vdot, current_5k_seconds,
  status, source, is_template, club_id, rules, notes
) VALUES (
  'a1a1eada-bbbb-0000-0000-000000000001',
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'Beginner 5K — Club Plan',
  'distance_5k', 5000, 1800,
  '2026-01-05', '2026-02-15', 3, 40.0, 1800,
  'completed', 'manual', true, 'c1111111-0000-0000-0000-000000000001',
  '["Run/walk early, build to continuous","Two easy runs + one long run each week","Rest days are part of the plan"]'::jsonb,
  'A gentle six-week introduction to 5K for new club members.'
);

INSERT INTO plan_weeks (id, plan_id, week_index, phase, target_volume_m, notes) VALUES
  ('a1aa0b01-0000-0000-0000-000000000001', 'a1a1eada-bbbb-0000-0000-000000000001', 0, 'base',  9000, 'Run/walk intervals'),
  ('a1aa0b02-0000-0000-0000-000000000002', 'a1a1eada-bbbb-0000-0000-000000000001', 1, 'base', 11000, 'Build continuous time on feet');

INSERT INTO plan_workouts (week_id, scheduled_date, kind, target_distance_m, target_pace_sec_per_km, target_pace_tolerance_sec, pace_zone, notes) VALUES
  ('a1aa0b01-0000-0000-0000-000000000001', '2026-01-06', 'easy', 3000, 420, 30, 'E', 'Run 2 min / walk 1 min x6'),
  ('a1aa0b01-0000-0000-0000-000000000001', '2026-01-08', 'easy', 3000, 420, 30, 'E', 'Run 2 min / walk 1 min x6'),
  ('a1aa0b01-0000-0000-0000-000000000001', '2026-01-10', 'long', 3500, 420, 45, 'E', 'Long run/walk, conversational'),
  ('a1aa0b02-0000-0000-0000-000000000002', '2026-01-13', 'easy', 3500, 410, 30, 'E', 'Run 3 min / walk 1 min x5'),
  ('a1aa0b02-0000-0000-0000-000000000002', '2026-01-15', 'easy', 3500, 410, 30, 'E', 'Run 3 min / walk 1 min x5'),
  ('a1aa0b02-0000-0000-0000-000000000002', '2026-01-17', 'long', 4000, 410, 45, 'E', 'Long run/walk');

-- ── Session plan template (yoga) ────────────────────────────────────────────
-- item.position is plan-global (the flat insert index), not per-block; blocks
-- carry their own 0..n position. Ordering below is the display order.
INSERT INTO session_plans (id, author_id, club_id, title, discipline, equipment, est_duration_min, is_public) VALUES
  ('5e551011-0000-0000-0000-000000000001',
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
   'c1111111-0000-0000-0000-000000000001',
   'Post-Run Recovery Flow', 'Vinyasa Yoga', 'Mat', 30, false);

INSERT INTO session_plan_blocks (id, plan_id, position, name) VALUES
  ('b10c0001-0000-0000-0000-000000000001', '5e551011-0000-0000-0000-000000000001', 0, 'Warm-up'),
  ('b10c0002-0000-0000-0000-000000000002', '5e551011-0000-0000-0000-000000000001', 1, 'Standing'),
  ('b10c0003-0000-0000-0000-000000000003', '5e551011-0000-0000-0000-000000000001', 2, 'Cool-down');

INSERT INTO session_plan_items (plan_id, block_id, position, movement_name, kind, duration_s, reps, per_side, cue) VALUES
  ('5e551011-0000-0000-0000-000000000001', 'b10c0001-0000-0000-0000-000000000001', 0, 'Child''s Pose', 'hold', 60, null, false, 'Breathe into the lower back'),
  ('5e551011-0000-0000-0000-000000000001', 'b10c0001-0000-0000-0000-000000000001', 1, 'Cat-Cow', 'flow', 45, null, false, 'Move with the breath'),
  ('5e551011-0000-0000-0000-000000000001', 'b10c0002-0000-0000-0000-000000000002', 2, 'Low Lunge', 'hold', 45, null, true, 'Sink the hips, lengthen the spine'),
  ('5e551011-0000-0000-0000-000000000001', 'b10c0002-0000-0000-0000-000000000002', 3, 'Downward Dog', 'hold', 60, null, false, 'Pedal the heels to free the calves'),
  ('5e551011-0000-0000-0000-000000000001', 'b10c0003-0000-0000-0000-000000000003', 4, 'Pigeon Pose', 'hold', 90, null, true, 'Glute + hip-flexor release'),
  ('5e551011-0000-0000-0000-000000000001', 'b10c0003-0000-0000-0000-000000000003', 5, 'Savasana', 'hold', 120, null, false, 'Full rest, let the breath settle');

-- ── Gym routine template (lower body) ───────────────────────────────────────
INSERT INTO gym_routines (id, author_id, club_id, title, notes, periodisation, exercise_count) VALUES
  ('61918001-0000-0000-0000-000000000001',
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
   'c1111111-0000-0000-0000-000000000001',
   'Club Strength — Lower Body', 'Pair with an easy run day. Leave 1-2 reps in reserve.', 'linear', 4);

INSERT INTO gym_routine_exercises (id, routine_id, exercise_name, exercise_key, position, modality, progression) VALUES
  ('e8e80001-0000-0000-0000-000000000001', '61918001-0000-0000-0000-000000000001', 'Back Squat', 'back squat', 0, 'weight_reps', 'linear'),
  ('e8e80002-0000-0000-0000-000000000002', '61918001-0000-0000-0000-000000000001', 'Romanian Deadlift', 'romanian deadlift', 1, 'weight_reps', 'linear'),
  ('e8e80003-0000-0000-0000-000000000003', '61918001-0000-0000-0000-000000000001', 'Walking Lunge', 'walking lunge', 2, 'weight_reps', 'none'),
  ('e8e80004-0000-0000-0000-000000000004', '61918001-0000-0000-0000-000000000001', 'Plank', 'plank', 3, 'time', 'none');

INSERT INTO gym_routine_sets (routine_exercise_id, set_index, set_type, target_reps_min, target_reps_max, target_weight_kg, rest_s, target_duration_s) VALUES
  ('e8e80001-0000-0000-0000-000000000001', 0, 'working', 5, 5, 60, 150, null),
  ('e8e80001-0000-0000-0000-000000000001', 1, 'working', 5, 5, 60, 150, null),
  ('e8e80001-0000-0000-0000-000000000001', 2, 'working', 5, 5, 60, 150, null),
  ('e8e80002-0000-0000-0000-000000000002', 0, 'working', 8, 10, 50, 120, null),
  ('e8e80002-0000-0000-0000-000000000002', 1, 'working', 8, 10, 50, 120, null),
  ('e8e80002-0000-0000-0000-000000000002', 2, 'working', 8, 10, 50, 120, null),
  ('e8e80003-0000-0000-0000-000000000003', 0, 'working', 10, 12, 20, 90, null),
  ('e8e80003-0000-0000-0000-000000000003', 1, 'working', 10, 12, 20, 90, null),
  ('e8e80004-0000-0000-0000-000000000004', 0, 'working', null, null, null, 60, 45),
  ('e8e80004-0000-0000-0000-000000000004', 1, 'working', null, null, null, 60, 45);

-- ── Coach roster (coach_roster.md) ──────────────────────────────────────────
-- runner@test.com coaches alex + morgan via two ACTIVE links so the /coaching
-- roster dashboard renders populated when the auto-login seed user signs in.
-- Both athletes carry recent runs from the seeding above, so the 7-day load /
-- recency columns are non-empty. Fixed ids → idempotent across resets.
INSERT INTO coach_athletes (id, coach_id, athlete_id, status, invite_token, accepted_at) VALUES
  ('ca000001-0000-0000-0000-000000000001',
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
   'b2c3d4e5-f6a7-8901-bcde-f23456789012',
   'active', 'seed-coach-roster-alex', now() - interval '30 days'),
  ('ca000002-0000-0000-0000-000000000002',
   'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
   'c3d4e5f6-a7b8-9012-cdef-345678901234',
   'active', 'seed-coach-roster-morgan', now() - interval '20 days');
