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
