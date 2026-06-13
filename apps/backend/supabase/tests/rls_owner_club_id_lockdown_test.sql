-- Pins migration 20270123_001 — the owner-policy club_id lockdown on
-- routes / training_plans / session_plans.
--
-- Contract:
--   1. a non-admin CANNOT inject a self-owned row into a club they don't
--      administer (the closed hole) — INSERT raises 42501 on all three.
--   2. the legitimate admin flows still work:
--        * an admin transfers their personal route into their club
--        * an admin publishes a club training-plan template
--        * an admin authors a club-owned session plan
--   3. personal rows (club_id null) still INSERT for any user.

begin;
select plan(9);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('77777777-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'admin@ocl.local', '', now(), now()),
  ('77777777-0000-0000-0000-0000000000a2', 'authenticated', 'authenticated', 'outsider@ocl.local', '', now(), now());

-- Club owned by the admin (the enroll_club_owner trigger auto-adds the
-- owner as an active 'owner' member). The outsider is NOT a member.
insert into clubs (id, owner_id, name, slug)
values ('cccccccc-0000-0000-0000-0000000000c1',
        '77777777-0000-0000-0000-0000000000a1', 'Lockdown Club', 'lockdown-club');

-- ───────────────── 1. the closed hole — outsider injection ─────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"77777777-0000-0000-0000-0000000000a2","role":"authenticated"}';

select throws_ok(
  $$ insert into routes (user_id, club_id, name, waypoints, distance_m)
     values ('77777777-0000-0000-0000-0000000000a2',
             'cccccccc-0000-0000-0000-0000000000c1', 'injected route', '[]'::jsonb, 1000) $$,
  '42501',
  'new row violates row-level security policy for table "routes"',
  'outsider cannot inject a self-owned route into a club they do not administer'
);

select throws_ok(
  $$ insert into training_plans (user_id, club_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, is_template)
     values ('77777777-0000-0000-0000-0000000000a2',
             'cccccccc-0000-0000-0000-0000000000c1', 'injected tmpl', 'distance_5k', 5000, current_date, current_date, 4, true) $$,
  '42501',
  'new row violates row-level security policy for table "training_plans"',
  'outsider cannot inject a self-owned template into a club they do not administer'
);

select throws_ok(
  $$ insert into session_plans (author_id, club_id, title)
     values ('77777777-0000-0000-0000-0000000000a2',
             'cccccccc-0000-0000-0000-0000000000c1', 'injected flow') $$,
  '42501',
  'new row violates row-level security policy for table "session_plans"',
  'outsider cannot inject a self-owned session plan into a club they do not administer'
);

-- A personal (club_id null) row of each still inserts for the outsider.
select lives_ok(
  $$ insert into routes (user_id, club_id, name, waypoints, distance_m)
     values ('77777777-0000-0000-0000-0000000000a2', null, 'my personal route', '[]'::jsonb, 1000) $$,
  'a personal route (club_id null) still inserts for any user'
);
select lives_ok(
  $$ insert into training_plans (user_id, club_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week)
     values ('77777777-0000-0000-0000-0000000000a2', null, 'my personal plan', 'distance_5k', 5000, current_date, current_date, 4) $$,
  'a personal training plan (club_id null) still inserts for any user'
);
select lives_ok(
  $$ insert into session_plans (author_id, club_id, title)
     values ('77777777-0000-0000-0000-0000000000a2', null, 'my personal flow') $$,
  'a personal session plan (club_id null) still inserts for any user'
);

-- ───────────────── 2. the legitimate admin flows still work ─────────────────
set local "request.jwt.claims" = '{"sub":"77777777-0000-0000-0000-0000000000a1","role":"authenticated"}';

-- Transfer a personal route into the admin's own club (setRouteClubId).
insert into routes (id, user_id, club_id, name, waypoints, distance_m)
values ('11111111-0000-0000-0000-000000000a01',
        '77777777-0000-0000-0000-0000000000a1', null, 'admin personal route', '[]'::jsonb, 1000);
select lives_ok(
  $$ update routes set club_id = 'cccccccc-0000-0000-0000-0000000000c1'
       where id = '11111111-0000-0000-0000-000000000a01' $$,
  'an admin can transfer their personal route into a club they administer'
);

-- Publish a club training-plan template (publishPlanAsTemplate).
select lives_ok(
  $$ insert into training_plans (user_id, club_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, is_template, status)
     values ('77777777-0000-0000-0000-0000000000a1',
             'cccccccc-0000-0000-0000-0000000000c1', 'club template', 'distance_5k', 5000, current_date, current_date, 4, true, 'completed') $$,
  'an admin can publish a club training-plan template'
);

-- Author a club-owned session plan (createSessionPlan with club_id).
select lives_ok(
  $$ insert into session_plans (author_id, club_id, title)
     values ('77777777-0000-0000-0000-0000000000a1',
             'cccccccc-0000-0000-0000-0000000000c1', 'club flow') $$,
  'an admin can author a club-owned session plan'
);

select * from finish();
rollback;
