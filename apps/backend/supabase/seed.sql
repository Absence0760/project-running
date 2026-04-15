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
