-- Pins the visibility contract the cross-modal following feed's LIFT branch
-- reads through (multi_modal.md § Social feed; web `fetchFollowingLifts` in
-- core/data.ts, mobile `_fetchFollowingLifts` in api_client.dart).
--
-- Issue #527: the mobile branch queried the BASE `gym_workouts` table, which
-- has been owner-only since 20270313_001 dropped its "owner or public read"
-- branch (that branch wire-leaked external_id / last_modified_at / notes /
-- metadata). A non-owner base-table read returns zero rows rather than
-- erroring, so every followee's public lift silently vanished from the feed
-- while the client still looked correct.
--
-- The existing rls_public_gym_food_column_lockdown_test pins the anon case
-- and the view's column set. This one pins the shape the FEED depends on —
-- an authenticated follower, both a public and a private workout by the same
-- followee — so neither half can regress:
--
--   under-report: the follower stops seeing the followee's PUBLIC lift
--   over-report:  the follower starts seeing the followee's PRIVATE lift
--
-- Runs are the reference contract here (`public_runs`, decisions §33); lifts
-- mirror it exactly, which is why nothing about `gym_workouts`' own RLS is
-- widened to fix #527.

begin;

select plan(8);

-- ── Fixture: a followee (owner) and a follower who is NOT the owner ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('0000f011-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'followee@lifts.local', '', now(), now()),
  ('0000f011-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'follower@lifts.local', '', now(), now());

-- Synthetic fixture users stand in for signed-up accounts, which always
-- carry the GDPR Art 8 stamp before they can write (20270424000004).
select tests.confirm_consent();

set local role service_role;

insert into public.user_follows (follower_id, followee_id)
values ('0000f011-0000-0000-0000-000000000002',
        '0000f011-0000-0000-0000-000000000001');

insert into public.gym_workouts (id, user_id, started_at, title, notes, is_public, external_id)
values
  ('0000f011-1111-1111-1111-111111111111',
   '0000f011-0000-0000-0000-000000000001',
   '2026-05-02 18:00:00+00', 'Squat day', 'hips felt tight', true, 'strava:551'),
  ('0000f011-2222-2222-2222-222222222222',
   '0000f011-0000-0000-0000-000000000001',
   '2026-05-03 18:00:00+00', 'Rehab session', 'shoulder physio', false, 'strava:552');

insert into public.gym_sets (workout_id, set_index, exercise_name, reps, weight_kg)
values
  ('0000f011-1111-1111-1111-111111111111', 0, 'Squat', 5, 100),
  ('0000f011-2222-2222-2222-222222222222', 0, 'Band pull-apart', 15, 5);

-- ── The follower: authenticated, entitled to the feed, NOT the owner ──
set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"0000f011-0000-0000-0000-000000000002","role":"authenticated"}';

select is(
  (select count(*)::int from gym_workouts
   where user_id = '0000f011-0000-0000-0000-000000000001'),
  0, 'a follower reads NOTHING of a followee off the base gym_workouts table');

-- The feed query shape: the followee set, the redacted view, the headline
-- projection. A public lift must land.
select is(
  (select count(*)::int
   from (select id, user_id, started_at, title, set_count, volume_kg
         from public_gym_workouts
         where user_id in ('0000f011-0000-0000-0000-000000000001')) f),
  1, 'a follower sees the followee''s PUBLIC lift through public_gym_workouts');

select is(
  (select title from public_gym_workouts
   where id = '0000f011-1111-1111-1111-111111111111'),
  'Squat day', 'the public lift''s headline columns are readable by the follower');

select is(
  (select count(*)::int from public_gym_workouts
   where id = '0000f011-2222-2222-2222-222222222222'),
  0, 'a follower does NOT see the followee''s PRIVATE lift through the view');

select is(
  (select count(*)::int from public_gym_sets
   where workout_id = '0000f011-1111-1111-1111-111111111111'),
  1, 'a follower sees the PUBLIC lift''s sets through public_gym_sets');

select is(
  (select count(*)::int from public_gym_sets
   where workout_id = '0000f011-2222-2222-2222-222222222222'),
  0, 'a follower does NOT see the PRIVATE lift''s sets');

-- Following someone does not widen the boundary: the view's predicate is
-- is_public, not the follow edge, so an unrelated stranger sees the same
-- public row and no more. Anything else would make the follow graph a
-- second, undocumented visibility tier.
set local role anon;
set local "request.jwt.claims" = '';

select is(
  (select count(*)::int from public_gym_workouts
   where user_id = '0000f011-0000-0000-0000-000000000001'),
  1, 'a non-follower sees exactly the same one public lift (is_public is the predicate, not the follow edge)');

-- The owner keeps the full row, redaction included (20260817_001 regression).
set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"0000f011-0000-0000-0000-000000000001","role":"authenticated"}';

select is(
  (select count(*)::int from gym_workouts
   where user_id = '0000f011-0000-0000-0000-000000000001'),
  2, 'the owner still reads both of their own workouts off the base table');

select * from finish();

rollback;
