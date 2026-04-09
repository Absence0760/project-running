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

-- 3. Routes
INSERT INTO routes (user_id, name, waypoints, distance_m, elevation_m, surface, is_public) VALUES
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Richmond Park Loop',
  '[{"lat":-37.8136,"lng":144.9631},{"lat":-37.8100,"lng":144.9700},{"lat":-37.8050,"lng":144.9650},{"lat":-37.8136,"lng":144.9631}]',
  10200, 85, 'trail', true),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Thames Path 5K',
  '[{"lat":-37.8200,"lng":144.9500},{"lat":-37.8180,"lng":144.9600}]',
  5000, 12, 'road', false),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Battersea Park Out & Back',
  '[{"lat":-37.8150,"lng":144.9550},{"lat":-37.8100,"lng":144.9700},{"lat":-37.8150,"lng":144.9550}]',
  7800, 20, 'road', true),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Sunday Long Run',
  '[{"lat":-37.8136,"lng":144.9631},{"lat":-37.7900,"lng":144.9800},{"lat":-37.8000,"lng":145.0000},{"lat":-37.8136,"lng":144.9631}]',
  21100, 140, 'mixed', false),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Commute Run',
  '[{"lat":-37.8180,"lng":144.9550},{"lat":-37.8100,"lng":144.9700}]',
  6400, 35, 'road', false);

-- 4. Runs (spanning ~3 weeks of realistic training)
INSERT INTO runs (user_id, started_at, duration_s, distance_m, source, metadata) VALUES
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-04-05T07:30:00Z', 1620, 5120, 'app', null),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-04-03T06:45:00Z', 2940, 10030, 'app', null),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-04-01T18:00:00Z', 1505, 5000, 'parkrun',
  '{"event":"Richmond","position":42,"age_grade":"54.23%"}'),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-03-30T07:00:00Z', 3780, 12500, 'strava', null),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-03-28T17:30:00Z', 1680, 5200, 'app', null),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-03-26T06:30:00Z', 5460, 21100, 'strava', null),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-03-25T07:15:00Z', 1500, 5000, 'parkrun',
  '{"event":"Bushy Park","position":38,"age_grade":"55.10%"}'),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-03-23T06:00:00Z', 2700, 8800, 'app', null),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-03-21T07:00:00Z', 1860, 6100, 'healthkit', null),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-03-19T18:15:00Z', 2400, 7600, 'app', null),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-03-17T06:45:00Z', 3300, 10100, 'strava', null),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', '2026-03-15T07:30:00Z', 1560, 5000, 'parkrun',
  '{"event":"Richmond","position":45,"age_grade":"53.80%"}');

-- 5. Integrations
INSERT INTO integrations (user_id, provider, last_sync_at) VALUES
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'parkrun', '2026-04-01T10:00:00Z'),
('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'strava', '2026-03-30T08:00:00Z');
